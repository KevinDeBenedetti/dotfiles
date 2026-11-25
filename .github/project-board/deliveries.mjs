// The report of the webhook deliveries the Worker failed
// (docs/config/issue-workflow.md#project-board): GitHub does not send them
// again, and shows them only on the App's Recent Deliveries page.
//
// Run by the hourly schedule: the deliveries of the hour before it that did
// not get a 2xx answer open one issue in REPORT_REPOSITORY, or are added to it
// while it is open. That repository is public: the report names the time,
// event, action and status of each delivery, never its repository or issue.
import { appClient, appLogin, installationClient } from "./github.mjs";

export const REPORT_TITLE = "Failed deliveries of the board Worker";
// The schedule's period: each run reports the hour before it.
const WINDOW_MS = 60 * 60e3;
// GitHub's largest page: an hour with more deliveries is reported in part.
const PAGE = 100;

const INTRO = "The board Worker answered these webhook deliveries with an error, and GitHub does not send them again. " +
  "The reason of each is on the App's Recent Deliveries (its Advanced settings page), where it can be redelivered; " +
  "the hourly reconcile puts the cards back in the column of their labels meanwhile.\n\n" +
  "Close this issue once the cause is fixed: the next failure opens a new one.";

const failedIn = (deliveries, from, to) => deliveries.filter((d) => {
  const at = Date.parse(d.delivered_at);
  return at >= from && at < to && !(d.status_code >= 200 && d.status_code < 300);
});

function table(failed) {
  const rows = failed.map((d) => `| ${d.delivered_at} | ${d.event} | ${d.action ?? ""} | ${d.status_code} |`);
  return ["| Time (UTC) | Event | Action | Status |", "| --- | --- | --- | --- |", ...rows].join("\n");
}

// reportFailedDeliveries(env, log, now): opens or updates the report for the
// deliveries of the hour before `now` that failed; nothing to write when none
// did, or when REPORT_REPOSITORY is not set.
export async function reportFailedDeliveries(env, log, now = Date.now()) {
  const repository = env.REPORT_REPOSITORY;
  if (!repository) return log("deliveries: REPORT_REPOSITORY is not set, not checked");

  const app = await appClient(env);
  const deliveries = await app(`/app/hook/deliveries?per_page=${PAGE}`);
  const failed = failedIn(deliveries, now - WINDOW_MS, now);
  if (!failed.length) return log("deliveries: 0 failed in the last hour");

  const issues = await installationClient(env, `/repos/${repository}/installation`);
  if (!issues) throw new Error(`The App is not installed on ${repository}: failed deliveries not reported`);
  // Newest first: a full page whose oldest delivery is still in the hour may
  // have left some of the hour out.
  const oldest = Date.parse(deliveries.at(-1)?.delivered_at);
  const partial = deliveries.length === PAGE && oldest >= now - WINDOW_MS
    ? "\n\nThe hour held more deliveries than one page: the earliest ones are missing." : "";
  const login = encodeURIComponent(await appLogin(env));
  const open = (await issues(`/repos/${repository}/issues?state=open&creator=${login}&per_page=100`))
    .find((issue) => issue.title === REPORT_TITLE && !issue.pull_request);
  if (open) {
    await issues(`/repos/${repository}/issues/${open.number}/comments`, {
      method: "POST", body: JSON.stringify({ body: `${table(failed)}${partial}` }),
    });
  } else {
    await issues(`/repos/${repository}/issues`, {
      method: "POST",
      body: JSON.stringify({ title: REPORT_TITLE, labels: ["needs-triage"], body: `${INTRO}\n\n${table(failed)}${partial}` }),
    });
  }
  return log(`deliveries: ${failed.length} failed in the last hour, reported in ${repository}`);
}
