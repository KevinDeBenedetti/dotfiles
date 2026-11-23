// Cloudflare Worker: the webhook receiver of a GitHub App that keeps the
// organization's board and the triage labels in step, both ways and as they
// happen (docs/config/issue-workflow.md#project-board):
//
// - issues (opened, reopened, labeled, unlabeled, closed): the issue is put on
//   the board, in the column of its labels;
// - projects_v2_item (edited): a card moved to another column sets the issue's
//   labels, and closes or reopens it.
//
// Vars (wrangler.toml): PROJECT_OWNER, PROJECT_NUMBER, REPOSITORY_OWNERS.
// Secrets (`wrangler secret put`): WEBHOOK_SECRET, GITHUB_APP_ID,
// GITHUB_APP_PRIVATE_KEY (PKCS#8), and BOARD_TOKEN.
//
// A GitHub App's installation sees one account only: the one on the
// organization cannot see a private issue of another account, and the one on
// that account cannot write the board. Those issues go through BOARD_TOKEN, a
// classic token (repo and project scopes); every other issue stays with the
// App, whose own writes the Worker recognises.
import { isTrackedRepository, loadProject, MISSING_BOARD_TOKEN, syncBoardToIssue, syncIssueToBoard } from "./board.mjs";
import { appLogin, client, installationClient } from "./github.mjs";

const ISSUE_ACTIONS = new Set(["opened", "reopened", "labeled", "unlabeled", "closed"]);

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

async function boardClient(env) {
  const gh = await installationClient(env, `/orgs/${env.PROJECT_OWNER}/installation`);
  if (!gh) throw new Error(`The App is not installed on ${env.PROJECT_OWNER}`);
  return gh;
}

const boardToken = (env) => (env.BOARD_TOKEN ? client(env.BOARD_TOKEN) : null);

async function onIssue(env, { action, issue, repository }) {
  if (!ISSUE_ACTIONS.has(action)) return reply("ignored: action", 202);
  if (!isTrackedRepository(env, repository.full_name)) return reply("ignored: another owner", 202);
  const hidden = repository.private && repository.owner.login.toLowerCase() !== env.PROJECT_OWNER.toLowerCase();
  if (hidden && !env.BOARD_TOKEN) throw new Error(MISSING_BOARD_TOKEN);
  const gh = hidden ? boardToken(env) : await boardClient(env);
  const stage = await syncIssueToBoard(gh, await loadProject(gh, env), issue.node_id);
  return reply(`${repository.full_name}#${issue.number} → ${stage}`);
}

async function onItem(env, { action, projects_v2_item: item, changes, sender }) {
  // A column change is an edit; moving a card within its column is a reorder.
  if (action !== "edited" || item?.content_type !== "Issue") return reply("ignored: action", 202);
  // The App's own writes (label to board) come back here: answering one could
  // undo a drag made meanwhile, and the labels already match it.
  if (sender?.type === "Bot" && sender.login === (await appLogin(env))) return reply("ignored: written by the App", 202);
  const gh = await boardClient(env);
  const issueClient = (repository) => installationClient(env, `/repos/${repository}/installation`);
  return reply(await syncBoardToIssue(gh, env, item.node_id, changes?.field_value?.field_node_id, issueClient, boardToken(env)));
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return reply("POST only", 405);
    const body = await request.text();
    if (!(await verify(body, request.headers.get("x-hub-signature-256"), env.WEBHOOK_SECRET))) {
      return reply("bad signature", 401);
    }
    const event = request.headers.get("x-github-event");
    try {
      if (event === "ping") return reply("pong");
      if (event === "issues") return await onIssue(env, JSON.parse(body));
      if (event === "projects_v2_item") return await onItem(env, JSON.parse(body));
      return reply("ignored: event", 202);
    } catch (error) {
      // GitHub shows the answer under the App's Recent Deliveries, where the
      // delivery can be sent again; it does not retry on its own.
      return reply(String(error.message ?? error), 500);
    }
  },
};
