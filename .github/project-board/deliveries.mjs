// The report of the webhook deliveries the Worker failed
// (docs/config/issue-workflow.md#project-board): GitHub does not send them
// again, and shows them only on the App's Recent Deliveries page.
//
// Run by the hourly schedule: the deliveries that did not get a 2xx answer
// since the last report open one issue in REPORT_REPOSITORY, or are added to
// it while it is open. That repository is public: the report names the time,
// event, action and status of each delivery, never its repository or issue.
//
// The time a report stops at is kept in its issue, as an HTML comment: the
// next one starts there, so a run that did not happen leaves no gap and a
// failure is never listed twice.
import { appClient, appLogin, installationClient } from "./github.mjs";

export const REPORT_TITLE = "Failed deliveries of the board Worker";
// The schedule's period: where a report starts when none was made before.
const WINDOW_MS = 60 * 60e3;
// GitHub's largest page: a report over more deliveries is made in part.
const PAGE = 100;

const INTRO = "The board Worker answered these webhook deliveries with an error, and GitHub does not send them again. " +
  "The reason of each is on the App's Recent Deliveries (its Advanced settings page), where it can be redelivered; " +
  "the hourly reconcile puts the cards back in the column of their labels meanwhile.\n\n" +
  "Close this issue once the cause is fixed: the next failure opens a new one.";

const failure = (d) => !(d.status_code >= 200 && d.status_code < 300);
const failedIn = (deliveries, from, to) => deliveries.filter((d) => {
  const at = Date.parse(d.delivered_at);
  return at >= from && at < to && failure(d);
});

// The end of a report, in its issue's body.
const MARKER = /<!-- reported-until: (\S+) -->/;
const marker = (until) => `<!-- reported-until: ${new Date(until).toISOString()} -->`;
const reportedUntil = (issue) => Date.parse(MARKER.exec(issue?.body ?? "")?.[1]);
// The body with its marker moved to `until`, or given one.
const marked = (body, until) => {
  const text = body ?? "";
  return MARKER.test(text) ? text.replace(MARKER, marker(until)) : `${text}\n\n${marker(until)}`;
};

function table(failed) {
  const rows = failed.map((d) => `| ${d.delivered_at} | ${d.event} | ${d.action ?? ""} | ${d.status_code} |`);
  return ["| Time (UTC) | Event | Action | Status |", "| --- | --- | --- | --- |", ...rows].join("\n");
}

// reportFailedDeliveries(env, log, now): opens or updates the report for the
// deliveries that failed since the last report (the hour before `now` when
// there is none); nothing to write when none did, or when REPORT_REPOSITORY
// is not set.
export async function reportFailedDeliveries(env, log, now = Date.now()) {
  const repository = env.REPORT_REPOSITORY;
  if (!repository) return log("deliveries: REPORT_REPOSITORY is not set, not checked");

  const app = await appClient(env);
  const deliveries = await app(`/app/hook/deliveries?per_page=${PAGE}`);
  // The usual run: nothing failed, so the last report is not read.
  if (!deliveries.some(failure)) return log("deliveries: 0 failed");

  const issues = await installationClient(env, `/repos/${repository}/installation`);
  if (!issues) throw new Error(`The App is not installed on ${repository}: failed deliveries not reported`);
  const login = encodeURIComponent(await appLogin(env));
  // The last report, closed or not: it holds where it stopped.
  const last = (await issues(`/repos/${repository}/issues?state=all&creator=${login}&sort=created&direction=desc&per_page=100`))
    .find((issue) => issue.title === REPORT_TITLE && !issue.pull_request);
  const until = reportedUntil(last);
  const from = Number.isNaN(until) ? now - WINDOW_MS : until;
  const since = `since ${new Date(from).toISOString()}`;
  const failed = failedIn(deliveries, from, now);
  if (!failed.length) return log(`deliveries: 0 failed ${since}`);

  // Newest first: a full page whose oldest delivery is still in the report's
  // window may have left some of it out.
  const oldest = Date.parse(deliveries.at(-1)?.delivered_at);
  const partial = deliveries.length === PAGE && oldest >= from
    ? "\n\nThere were more deliveries than one page since the last report: the earliest ones are missing." : "";
  if (last?.state === "open") {
    // The comment first: a marker that could not be moved repeats these
    // failures in the next report, it never hides the ones after them.
    await issues(`/repos/${repository}/issues/${last.number}/comments`, {
      method: "POST", body: JSON.stringify({ body: `${table(failed)}${partial}` }),
    });
    await issues(`/repos/${repository}/issues/${last.number}`, {
      method: "PATCH", body: JSON.stringify({ body: marked(last.body, now) }),
    });
  } else {
    await issues(`/repos/${repository}/issues`, {
      method: "POST",
      body: JSON.stringify({
        title: REPORT_TITLE, labels: ["needs-triage"],
        body: `${INTRO}\n\n${table(failed)}${partial}\n\n${marker(now)}`,
      }),
    });
  }
  return log(`deliveries: ${failed.length} failed ${since}, reported in ${repository}`);
}
