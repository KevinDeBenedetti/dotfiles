// From a card's Stage column to the issue's labels and state: the reverse of
// .github/scripts/project-stage.sh, whose stage_for() this mirrors. Keep both
// in step (docs/config/issue-workflow.md#project-board).

// Column name → the triage label it stands for (Done has none).
const COLUMNS = {
  "Needs triage": "needs-triage",
  "Needs info": "needs-info",
  "Ready for agent": "ready-for-agent",
  "Ready for human": "ready-for-human",
  "Won't fix": "wontfix",
  "Done": null,
};

const TRIAGE = Object.values(COLUMNS).filter(Boolean);

const normalize = (name) => name.trim().toLowerCase();

// The column of an issue, as project-stage.sh computes it: when several
// triage labels are set, the one that stops the work wins.
export function stageFor(labels, state) {
  if (labels.includes("wontfix")) return "Won't fix";
  if (state === "CLOSED") return "Done";
  if (labels.includes("needs-info")) return "Needs info";
  if (labels.includes("ready-for-human")) return "Ready for human";
  if (labels.includes("ready-for-agent")) return "Ready for agent";
  return "Needs triage";
}

// planFor(column, labels, state, stateReason): the body of the issue update
// that puts the issue in that column, or null when nothing is to change
// (unknown column, or the issue is already there). Labels other than the
// triage ones are kept.
export function planFor(column, labels, state, stateReason) {
  const stage = Object.keys(COLUMNS).find((name) => normalize(name) === normalize(column ?? ""));
  if (!stage || stageFor(labels, state) === stage) return null;

  if (stage === "Done") {
    // A closed issue is Done whatever its other triage labels: they stay as
    // its history.
    return { labels: labels.filter((l) => l !== "wontfix"), state: "closed", state_reason: "completed" };
  }
  const update = { labels: [...labels.filter((l) => !TRIAGE.includes(l)), COLUMNS[stage]] };
  if (stage === "Won't fix") {
    if (state !== "CLOSED" || stateReason !== "NOT_PLANNED") {
      Object.assign(update, { state: "closed", state_reason: "not_planned" });
    }
  } else if (state === "CLOSED") {
    update.state = "open";
  }
  return update;
}
