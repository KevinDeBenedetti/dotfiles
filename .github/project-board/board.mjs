// The two sync directions between the triage labels and the board's Stage
// column (docs/config/issue-workflow.md#project-board), and the backfill.
//
// Both directions read the issue back from GitHub instead of trusting the
// delivery, and leave alone what is already in step: that is how they stop
// each other.
import { GitHubError, graphql } from "./github.mjs";
import { optionFor, planFor, stageFor } from "./plan.mjs";

const PROJECT_QUERY = `query($owner: String!, $number: Int!) {
  organization(login: $owner) {
    projectV2(number: $number) {
      id
      field(name: "Stage") { ... on ProjectV2SingleSelectField { id options { id name } } }
    }
  }
}`;

// The item's current column and its issue as it is now, read in the call that
// adds it (adding an issue already on the board returns its item). Reading the
// issue any earlier would leave time for a drag to be overwritten.
const ADD_ITEM = `mutation($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
    item {
      id
      stage: fieldValueByName(name: "Stage") { ... on ProjectV2ItemFieldSingleSelectValue { optionId } }
      content { ... on Issue { number state labels(first: 100) { nodes { name } } } }
    }
  }
}`;

const SET_STAGE = `mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId,
    value: {singleSelectOptionId: $optionId}}) { projectV2Item { id } }
}`;

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

// isTrackedRepository(env, repository): whether the triage labels apply to
// that repository (owner/name). The App is public, so anyone may install it.
export function isTrackedRepository(env, repository) {
  const owners = (env.REPOSITORY_OWNERS ?? "").split(",").map((o) => o.trim().toLowerCase());
  return owners.includes(repository.split("/")[0].toLowerCase());
}

const labelNames = (issue) => issue.labels.nodes.map((label) => label.name);

// loadProject(gh, env): the board's ids and Stage options.
export async function loadProject(gh, env) {
  const data = await graphql(gh, PROJECT_QUERY, { owner: env.PROJECT_OWNER, number: Number(env.PROJECT_NUMBER) });
  const project = data?.organization?.projectV2;
  if (!project) throw new Error(`Project ${env.PROJECT_NUMBER} of ${env.PROJECT_OWNER} not found, or not readable`);
  if (!project.field?.id) throw new Error(`Project ${env.PROJECT_NUMBER} has no single-select field named Stage`);
  return { id: project.id, fieldId: project.field.id, options: project.field.options };
}

// Writes made from labels that changed meanwhile are caught by reading the
// issue again; this many writes at most, in one delivery.
const MAX_WRITES = 3;

// syncIssueToBoard(gh, project, issueId): puts the issue on the board, in the
// column of its labels now. gh carries the organization's token.
//
// Deliveries run in parallel: one that read older labels may write after one
// that read newer labels. So after a write the issue is read again, and the
// column written again if the issue changed meanwhile.
export async function syncIssueToBoard(gh, project, issueId) {
  let written = null;
  for (let writes = 0; ; writes++) {
    const { item } = (await graphql(gh, ADD_ITEM, { projectId: project.id, contentId: issueId })).addProjectV2ItemById;
    const stage = stageFor(labelNames(item.content), item.content.state);
    const option = optionFor(project.options, stage);
    if (!option) {
      const names = project.options.map((o) => `'${o.name}'`).join(", ");
      throw new Error(`The Stage field has no '${stage}' option (${names ? `it has: ${names}` : "it has no options yet"})`);
    }
    if (item.stage?.optionId === option || option === written || writes === MAX_WRITES) {
      return written ? stage : `${stage} (already there)`;
    }
    await graphql(gh, SET_STAGE, { projectId: project.id, itemId: item.id, fieldId: project.fieldId, optionId: option });
    written = option;
  }
}

// readItem(gh, itemId): the card and its issue, or null when the token cannot
// see the issue (GitHub hides it, or answers with an error).
async function readItem(gh, itemId) {
  try {
    const item = (await graphql(gh, ITEM_QUERY, { id: itemId }))?.node;
    return item?.content?.number ? item : null;
  } catch (error) {
    if (error instanceof GitHubError) return null;
    throw error;
  }
}

export const MISSING_BOARD_TOKEN = "The App cannot see a private issue of another account than the board's: " +
  "set the BOARD_TOKEN secret (classic token, repo and project scopes)";

// syncBoardToIssue(gh, env, itemId, fieldId, issueClient, boardToken): sets the
// issue's labels and state from its card's column. gh carries the
// organization's token; boardToken, a client with BOARD_TOKEN or null, reads
// the cards whose issue gh cannot see (private, of another account).
// issueClient(repository) returns a client for the repository's installation,
// or null. fieldId is the field the delivery says was edited.
export async function syncBoardToIssue(gh, env, itemId, fieldId, issueClient, boardToken) {
  let item = await readItem(gh, itemId);
  if (!item) {
    if (!boardToken) throw new Error(MISSING_BOARD_TOKEN);
    item = await readItem(boardToken, itemId);
  }
  const issue = item?.content;
  if (!issue) return "ignored: not an issue";
  if (item.project.owner.login !== env.PROJECT_OWNER || String(item.project.number) !== String(env.PROJECT_NUMBER)) {
    return "ignored: another project";
  }
  const repository = issue.repository.nameWithOwner;
  if (!isTrackedRepository(env, repository)) return "ignored: another owner";
  // Another field was edited: a label change may still be on its way to the
  // Stage column, and re-applying the column now would undo it.
  if (fieldId && item.stage?.field?.id && fieldId !== item.stage.field.id) return "ignored: another field";

  const update = planFor(item.stage?.name, labelNames(issue), issue.state, issue.stateReason);
  if (!update) return "in step";
  const issueApi = await issueClient(repository);
  if (!issueApi) return `ignored: the App is not installed on ${repository}`;
  await issueApi(`/repos/${repository}/issues/${issue.number}`, { method: "PATCH", body: JSON.stringify(update) });
  return `${repository}#${issue.number} updated`;
}

// backfill(gh, env, repositories, log): puts every open issue of those
// repositories on the board. gh needs the `project` and `repo` scopes.
export async function backfill(gh, env, repositories, log) {
  const project = await loadProject(gh, env);
  for (const repository of repositories) {
    for (let page = 1; ; page++) {
      const issues = await gh(`/repos/${repository}/issues?state=open&per_page=100&page=${page}`);
      if (!issues.length) break;
      // The issues endpoint lists pull requests too.
      for (const issue of issues.filter((i) => !i.pull_request)) {
        log(`${repository}#${issue.number} → ${await syncIssueToBoard(gh, project, issue.node_id)}`);
      }
    }
  }
}
