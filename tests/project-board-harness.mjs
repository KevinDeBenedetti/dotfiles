// Runs the project-board Worker (.github/project-board/worker.mjs) once, on a
// webhook delivery built from the environment, with GitHub's API replaced by
// a fake. Prints one line per API call ("<METHOD> <path> <body>"), then the
// Worker's answer ("=> <status> <text>"). Driven by tests/project-board.bats.
//
// Env:
//   EVENT       X-GitHub-Event header (default projects_v2_item)
//   PAYLOAD     the delivery's JSON body
//   SIGNATURE   good (default), bad or none
//   ITEM        JSON the fake GraphQL API returns as the project item
//   VARS        JSON of the Worker's vars, merged over the defaults below
import { createHmac } from "node:crypto";
import { pathToFileURL } from "node:url";

const [, , workerPath] = process.argv;
const { default: worker } = await import(pathToFileURL(workerPath).href);

const env = {
  WEBHOOK_SECRET: "test-secret",
  GITHUB_TOKEN: "test-token",
  PROJECT_OWNER: "labs",
  PROJECT_NUMBER: "1",
  REPOSITORIES: "owner/repo",
  ...JSON.parse(process.env.VARS || "{}"),
};

globalThis.fetch = async (input, init = {}) => {
  const url = new URL(typeof input === "string" ? input : input.url);
  const body = init.body ?? "";
  const auth = new Headers(init.headers).get("authorization");
  if (auth !== "Bearer test-token") throw new Error(`unexpected auth: ${auth}`);
  if (url.pathname === "/graphql") {
    console.log(`GRAPHQL ${JSON.parse(body).variables.id}`);
    return Response.json({ data: { node: JSON.parse(process.env.ITEM || "null") } });
  }
  console.log(`${init.method ?? "GET"} ${url.pathname} ${body}`.trimEnd());
  return Response.json({});
};

const payload = process.env.PAYLOAD ?? "{}";
const headers = { "x-github-event": process.env.EVENT ?? "projects_v2_item" };
const signature = process.env.SIGNATURE ?? "good";
if (signature !== "none") {
  const key = signature === "good" ? env.WEBHOOK_SECRET : "wrong-secret";
  headers["x-hub-signature-256"] =
    "sha256=" + createHmac("sha256", key).update(payload).digest("hex");
}

const method = process.env.METHOD ?? "POST";
const response = await worker.fetch(
  new Request("https://worker.test/", { method, headers, body: method === "POST" ? payload : undefined }),
  env,
);
console.log(`=> ${response.status} ${await response.text()}`);
