// Cloudflare Worker: when a card is moved on the organization's project board,
// set the issue's triage label from its Stage column, and close or reopen it
// (docs/config/issue-workflow.md#from-the-board-to-the-labels). It receives
// the organization webhook's projects_v2_item deliveries: GitHub sends no such
// event for a project owned by a user, and Actions cannot trigger on it.
//
// Vars (wrangler.toml): PROJECT_OWNER, PROJECT_NUMBER, REPOSITORIES (comma-
// separated owner/name). Secrets (`wrangler secret put`): WEBHOOK_SECRET, the
// webhook's secret; GITHUB_TOKEN, a classic token with the `public_repo` and
// `read:project` scopes.
//
// The issue is read back from the API, never taken from the delivery, and
// updated in one call. An item already in step with its issue changes
// nothing: that is what stops the label-to-board workflow, whose own edit
// comes back here, from bouncing between the two.
import { planFor } from "./plan.mjs";

const API = "https://api.github.com";

const ITEM_QUERY = `query($id: ID!) {
  node(id: $id) {
    ... on ProjectV2Item {
      project { number owner { ... on Organization { login } ... on User { login } } }
      stage: fieldValueByName(name: "Stage") {
        ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2SingleSelectField { id } } }
      }
      content {
        ... on Issue {
          number state stateReason
          labels(first: 100) { nodes { name } }
          repository { nameWithOwner }
        }
      }
    }
  }
}`;

const reply = (body, status = 200) => new Response(body, { status });

// verify(body, header, secret): whether X-Hub-Signature-256 is the HMAC of the
// body. crypto.subtle.verify compares in constant time.
async function verify(body, header, secret) {
  const hex = /^sha256=([0-9a-f]{64})$/.exec(header ?? "")?.[1];
  if (!hex || !secret) return false;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const signature = Uint8Array.from(hex.match(/../g), (byte) => parseInt(byte, 16));
  return crypto.subtle.verify("HMAC", key, signature, enc.encode(body));
}

async function github(env, path, init = {}) {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "user-agent": "project-board-worker",
      "x-github-api-version": "2022-11-28",
    },
  });
  if (!response.ok) throw new Error(`${init.method ?? "GET"} ${path}: ${response.status} ${await response.text()}`);
  return response.json();
}

// sync(env, itemId, fieldId): fieldId is the field the delivery says was
// edited, when it says so.
async function sync(env, itemId, fieldId) {
  const { data, errors } = await github(env, "/graphql", {
    method: "POST",
    body: JSON.stringify({ query: ITEM_QUERY, variables: { id: itemId } }),
  });
  if (errors) throw new Error(`GraphQL: ${JSON.stringify(errors)}`);
  const item = data?.node;
  const issue = item?.content;
  if (!issue?.number) return "ignored: not an issue";
  if (item.project.owner.login !== env.PROJECT_OWNER || String(item.project.number) !== String(env.PROJECT_NUMBER)) {
    return "ignored: another project";
  }
  const repositories = (env.REPOSITORIES ?? "").split(",").map((r) => r.trim().toLowerCase());
  if (!repositories.includes(issue.repository.nameWithOwner.toLowerCase())) return "ignored: another repository";

  // Another field was edited: a label change may still be on its way to the
  // Stage column, and re-applying the column now would undo it.
  if (fieldId && item.stage?.field?.id && fieldId !== item.stage.field.id) return "ignored: another field";

  const labels = issue.labels.nodes.map((l) => l.name);
  const update = planFor(item.stage?.name, labels, issue.state, issue.stateReason);
  if (!update) return "in step";
  await github(env, `/repos/${issue.repository.nameWithOwner}/issues/${issue.number}`, {
    method: "PATCH",
    body: JSON.stringify(update),
  });
  return `#${issue.number} updated`;
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return reply("POST only", 405);
    const body = await request.text();
    if (!(await verify(body, request.headers.get("x-hub-signature-256"), env.WEBHOOK_SECRET))) {
      return reply("bad signature", 401);
    }
    const event = request.headers.get("x-github-event");
    if (event === "ping") return reply("pong");
    if (event !== "projects_v2_item") return reply("ignored: event", 202);

    const { action, projects_v2_item: item, changes } = JSON.parse(body);
    // A column change is an edit; moving a card within its column is a
    // reorder, and touches no field.
    if (action !== "edited" || item?.content_type !== "Issue") return reply("ignored: action", 202);
    // An error answers 500: GitHub records the failed delivery, and it can be
    // redelivered from the webhook's settings.
    return reply(await sync(env, item.node_id, changes?.field_value?.field_node_id));
  },
};
