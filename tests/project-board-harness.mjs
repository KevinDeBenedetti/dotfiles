// Runs the project-board Worker (.github/project-board/) against a fake
// GitHub, for tests/project-board.bats. Prints one line per API call, then
// the result: "=> <status> <text>" for a webhook delivery (MODE=deliver, the
// default), or the backfill's own lines (MODE=backfill).
//
// The fake GitHub checks the App's JWT before it issues an installation
// token ("inst-<id>"), and logs which token each call used.
//
// Env:
//   EVENT, PAYLOAD   the delivery's X-GitHub-Event header and JSON body
//   SIGNATURE        good (default), bad or none
//   METHOD           the request's method (default POST)
//   KEY_FORMAT       pkcs8 (default) or pkcs1: how the App's key is stored
//   VARS             JSON merged over the Worker's default vars
//   INSTALLED        JSON map: account login → installation id
//   ITEM             the project item, for an item query
//   HIDDEN_ITEM      null or error: what an App token gets instead of the
//                    item's issue, as for a private issue of another account;
//                    BOARD_TOKEN ("board-pat") always sees it
//   ISSUE            the issue as it is now ({number,state,labels}), and
//   ISSUE_AFTER      as it is on the next add (default: unchanged), and
//   CURRENT_OPTION   the option id its item has, for the add mutation
//   OPTIONS          JSON array of the Stage field's options ({id,name})
//   REPO_ISSUES      JSON map: repository → its open issues (MODE=backfill)
//   REPOS            space-separated repositories to backfill
import { createHmac, createVerify, generateKeyPairSync } from "node:crypto";
import { pathToFileURL } from "node:url";

const [, , boardDir] = process.argv;
const load = (name) => import(pathToFileURL(`${boardDir}/${name}`).href);

const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const keyFormat = process.env.KEY_FORMAT ?? "pkcs8";
const env = {
  WEBHOOK_SECRET: "test-secret",
  GITHUB_APP_ID: "123",
  GITHUB_APP_PRIVATE_KEY: privateKey.export({ type: keyFormat, format: "pem" }),
  BOARD_TOKEN: "board-pat",
  PROJECT_OWNER: "labs",
  PROJECT_NUMBER: "1",
  REPOSITORY_OWNERS: "owner,labs",
  ...JSON.parse(process.env.VARS || "{}"),
};

const json = (name, fallback) => JSON.parse(process.env[name] || fallback);
const installed = json("INSTALLED", '{"owner":11,"labs":22}');
const options = json("OPTIONS", JSON.stringify([
  { id: "OPT_TRIAGE", name: "Needs triage" }, { id: "OPT_INFO", name: "Needs info" },
  { id: "OPT_AGENT", name: "Ready for agent" }, { id: "OPT_HUMAN", name: "Ready for human" },
  { id: "OPT_WONTFIX", name: "Won't fix" }, { id: "OPT_DONE", name: "Done" },
]));

function verifyJwt(jwt) {
  const [header, payload, signature] = jwt.split(".");
  const ok = createVerify("RSA-SHA256").update(`${header}.${payload}`).verify(publicKey, signature, "base64url");
  const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
  const now = Math.floor(Date.now() / 1000);
  if (!ok || claims.iss !== env.GITHUB_APP_ID || claims.exp <= now || claims.exp - claims.iat > 600) {
    throw new Error(`fake GitHub: bad JWT ${JSON.stringify(claims)}`);
  }
}

let adds = 0;
// REVOKED: installations whose first token is stale (as a cached token after
// the App was reinstalled): GitHub refuses it, and issues a good one next.
const revoked = new Set((process.env.REVOKED ?? "").split(" ").filter(Boolean));
const issued = new Set();

const notFound = () => Response.json({ message: "Not Found" }, { status: 404 });

globalThis.fetch = async (input, init = {}) => {
  const url = new URL(typeof input === "string" ? input : input.url);
  const method = init.method ?? "GET";
  const token = new Headers(init.headers).get("authorization")?.replace(/^Bearer /, "");
  const body = init.body ?? "";
  let match;

  // App endpoints: authenticated by the JWT.
  if (url.pathname === "/app") {
    verifyJwt(token);
    return Response.json({ slug: "board-app" });
  }
  if ((match = /^\/orgs\/([^/]+)\/installation$/.exec(url.pathname)) ||
      (match = /^\/repos\/([^/]+)\/[^/]+\/installation$/.exec(url.pathname))) {
    verifyJwt(token);
    const id = installed[match[1]];
    return id ? Response.json({ id }) : notFound();
  }
  if ((match = /^\/app\/installations\/(\d+)\/access_tokens$/.exec(url.pathname))) {
    verifyJwt(token);
    const stale = revoked.has(match[1]) && !issued.has(match[1]);
    issued.add(match[1]);
    const name = stale ? `inst-${match[1]}-stale` : `inst-${match[1]}`;
    console.log(`TOKEN ${name}`);
    return Response.json({ token: name, expires_at: new Date(Date.now() + 3600e3).toISOString() });
  }

  if (token?.endsWith("-stale")) {
    console.log(`REFUSED ${token}`);
    return Response.json({ message: "Bad credentials" }, { status: 401 });
  }

  if (url.pathname === "/graphql") {
    const { query, variables } = JSON.parse(body);
    if (query.includes("addProjectV2ItemById")) {
      console.log(`GRAPHQL add ${variables.contentId} as ${token}`);
      const first = process.env.ISSUE || '{"number":7,"state":"OPEN","labels":[]}';
      const issue = JSON.parse(adds++ === 0 ? first : process.env.ISSUE_AFTER || first);
      return Response.json({ data: { addProjectV2ItemById: { item: {
        id: `ITEM_${variables.contentId}`,
        stage: process.env.CURRENT_OPTION ? { optionId: process.env.CURRENT_OPTION } : null,
        content: { number: issue.number, state: issue.state, labels: { nodes: issue.labels.map((name) => ({ name })) } },
      } } } });
    }
    if (query.includes("updateProjectV2ItemFieldValue")) {
      console.log(`GRAPHQL update ${variables.itemId} ${variables.optionId} as ${token}`);
      return Response.json({ data: { updateProjectV2ItemFieldValue: { projectV2Item: { id: variables.itemId } } } });
    }
    if (query.includes("projectV2(number")) {
      console.log(`GRAPHQL project ${variables.owner}/${variables.number} as ${token}`);
      return Response.json({ data: { organization: { projectV2: {
        id: "PVT_1", field: { id: "FIELD_STAGE", options },
      } } } });
    }
    console.log(`GRAPHQL item ${variables.id} as ${token}`);
    const item = json("ITEM", "null");
    const hidden = process.env.HIDDEN_ITEM;
    if (hidden && token !== "board-pat") {
      if (hidden === "error") {
        return Response.json({ data: { node: { ...item, content: null } },
          errors: [{ type: "FORBIDDEN", message: "Resource not accessible by integration" }] });
      }
      return Response.json({ data: { node: { ...item, content: null } } });
    }
    return Response.json({ data: { node: item } });
  }

  if (method === "GET" && (match = /^\/repos\/([^/]+\/[^/]+)\/issues$/.exec(url.pathname))) {
    const issues = json("REPO_ISSUES", "{}")[match[1]] ?? [];
    const page = Number(url.searchParams.get("page") ?? 1);
    console.log(`LIST ${match[1]} page ${page} as ${token}`);
    return Response.json(page === 1 ? issues : []);
  }

  console.log(`${method} ${url.pathname} ${body} as ${token}`);
  return Response.json({});
};

if (process.env.MODE === "backfill") {
  const { client } = await load("github.mjs");
  const { backfill } = await load("board.mjs");
  const repos = (process.env.REPOS ?? "").split(" ").filter(Boolean);
  await backfill(client("pat"), env, repos, (line) => console.log(line));
} else {
  const { default: worker } = await load("worker.mjs");
  const payload = process.env.PAYLOAD ?? "{}";
  const headers = { "x-github-event": process.env.EVENT ?? "projects_v2_item" };
  const signature = process.env.SIGNATURE ?? "good";
  if (signature !== "none") {
    const key = signature === "good" ? env.WEBHOOK_SECRET : "wrong-secret";
    headers["x-hub-signature-256"] = "sha256=" + createHmac("sha256", key).update(payload).digest("hex");
  }
  const method = process.env.METHOD ?? "POST";
  const response = await worker.fetch(
    new Request("https://worker.test/", { method, headers, body: method === "POST" ? payload : undefined }),
    env,
  );
  console.log(`=> ${response.status} ${await response.text()}`);
}
