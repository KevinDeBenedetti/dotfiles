// The mapping between an issue's triage labels and its Stage column on the
// board, both ways (docs/config/issue-workflow.md#project-board).

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
// sameName(a, b): whether two column names match, whatever their case and
// surrounding spaces.
const sameName = (a, b) => normalize(a ?? "") === normalize(b ?? "");

// The column of an issue: when several triage labels are set, the one that
// stops the work wins.
export function stageFor(labels, state) {
  if (labels.includes("wontfix")) return "Won't fix";
  if (state === "CLOSED") return "Done";
  if (labels.includes("needs-info")) return "Needs info";
  if (labels.includes("ready-for-human")) return "Ready for human";
  if (labels.includes("ready-for-agent")) return "Ready for agent";
  return "Needs triage";
}

// optionFor(options, stage): the id of the Stage field's option for that
// column, matched whatever its case and surrounding spaces.
export function optionFor(options, stage) {
  return options.find((option) => sameName(option.name, stage))?.id;
}

// planFor(column, labels, state, stateReason): the body of the issue update
// that puts the issue in that column, or null when nothing is to change
// (unknown column, or the issue is already there). Labels other than the
// triage ones are kept.
export function planFor(column, labels, state, stateReason) {
  const stage = Object.keys(COLUMNS).find((name) => sameName(name, column));
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
