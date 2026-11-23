// GitHub API access for the project-board Worker: a small REST/GraphQL client,
// and the GitHub App's installation tokens.
//
// The App is installed twice: on the account owning the repositories (Issues)
// and on the organization owning the board (Projects). Each call takes the
// token of the installation that owns what it touches.

const API = "https://api.github.com";

export class GitHubError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

// client(token): a function (path, init) → parsed JSON body, throwing a
// GitHubError on a non-2xx answer or a GraphQL error.
export function client(token) {
  return async (path, init = {}) => {
    const response = await fetch(`${API}${path}`, {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        accept: "application/vnd.github+json",
        "content-type": "application/json",
        "user-agent": "project-board-worker",
        "x-github-api-version": "2022-11-28",
      },
    });
    const text = await response.text();
    if (!response.ok) throw new GitHubError(`${init.method ?? "GET"} ${path}: ${response.status} ${text}`, response.status);
    const body = text ? JSON.parse(text) : null;
    if (body?.errors) throw new GitHubError(`${path}: ${JSON.stringify(body.errors)}`, response.status);
    return body;
  };
}

// graphql(gh, query, variables): the data of a GraphQL query.
export async function graphql(gh, query, variables) {
  return (await gh("/graphql", { method: "POST", body: JSON.stringify({ query, variables }) })).data;
}

const base64url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
const encode = (value) => base64url(new TextEncoder().encode(JSON.stringify(value)));

async function importKey(pem) {
  // The PKCS#1 header, assembled so secret scanners do not take this line for
  // a key.
  if (pem.includes("BEGIN RSA " + "PRIVATE KEY")) {
    throw new Error("GITHUB_APP_PRIVATE_KEY is in GitHub's PKCS#1 format: convert it with " +
      "`openssl pkcs8 -topk8 -nocrypt -in <key>.pem`, then store the output");
  }
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

// The App's own JWT, valid 9 minutes (GitHub accepts 10 at most), backdated a
// minute against clock drift.
async function appJwt(env) {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({ iat: now - 60, exp: now + 540, iss: env.GITHUB_APP_ID })}`;
  const key = await importKey(env.GITHUB_APP_PRIVATE_KEY);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(signature)}`;
}

// Tokens live an hour; a Worker instance serving several deliveries reuses them.
const tokens = new Map();

// newToken(env, lookup): a fresh token of the installation found at lookup,
// or null when the App is not installed there.
async function newToken(env, lookup) {
  const app = client(await appJwt(env));
  let installation;
  try {
    installation = await app(lookup);
  } catch (error) {
    if (error.status === 404) return null;
    throw error;
  }
  const { token, expires_at } = await app(`/app/installations/${installation.id}/access_tokens`, { method: "POST" });
  tokens.set(lookup, { token, expires: Date.parse(expires_at) });
  return token;
}

// installationClient(env, lookup): a client with the token of the installation
// that GitHub finds at `lookup` (/orgs/<org>/installation,
// /repos/<owner>/<name>/installation), or null when the App is not installed
// there. A token GitHub refuses (one cached across a reinstall of the App) is
// replaced once, and the call made again.
export async function installationClient(env, lookup) {
  const cached = tokens.get(lookup);
  let token = cached && cached.expires - Date.now() > 5 * 60e3 ? cached.token : await newToken(env, lookup);
  if (!token) return null;
  return async (path, init) => {
    try {
      return await client(token)(path, init);
    } catch (error) {
      if (error.status !== 401) throw error;
      tokens.delete(lookup);
      token = await newToken(env, lookup);
      if (!token) throw error;
      return client(token)(path, init);
    }
  };
}

let slug;

// appLogin(env): the login the App writes as ("<slug>[bot]").
export async function appLogin(env) {
  slug ??= (await client(await appJwt(env))("/app")).slug;
  return `${slug}[bot]`;
}
