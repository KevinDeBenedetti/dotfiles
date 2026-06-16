Debug a failing GitHub Actions run. The argument is a run/job URL, a run ID, or
a pasted error log. If nothing is given, find the most recent failed run for the
current repo.

Gather context (read-only):
1. If `gh` is available, fetch the failure with:
   - `gh run list --status failure --limit 5`
   - `gh run view <run-id> --log-failed` (or `--log` for the full log)
   - `gh run view <run-id> --json jobs,workflowName,headBranch,event,conclusion`
   Otherwise work from the pasted log.
2. Identify the failing workflow, job, step, and the `runs-on` target. Note
   whether it ran on a **github-hosted** runner (`ubuntu-latest`, …) or a
   **self-hosted** runner (label set / ARC scale set).

Diagnose — find the root cause, not just the surface error. Consider:
- **App / build errors**: failing tests, compile/lint errors, missing env vars
  or secrets, dependency/lockfile mismatch, wrong working directory.
- **Self-hosted runner issues** (check these when `runs-on` is self-hosted):
  label mismatch (no runner matches the requested labels), tool/runtime missing
  from the runner image, disk space / cache exhaustion, leftover state from a
  previous job, permissions, network/DNS or registry access from inside the
  cluster, ARC scale-set not scaling up.
- **github-hosted issues**: tool version drift on the image, rate limits,
  ephemeral network failures, timeouts.
- **Workflow config**: bad `permissions:`, missing secrets in the right scope,
  matrix/`if` conditions, expression typos, action version problems.

Report:
1. **Root cause** — one clear sentence.
2. **Evidence** — the exact log lines / step that prove it (file:line for
   workflow config).
3. **Fix** — concrete diff or command. Distinguish "fix in the app/repo" from
   "fix on the runner / infra".
4. **Reproduce locally** when feasible (the failing command, `act`, or the
   container image used) so the loop is fast.
5. **Prevent recurrence** — pin a version, add a guard, cache, healthcheck, etc.

Do not re-run, cancel, or modify workflows/secrets without being asked — first
diagnose and propose.
