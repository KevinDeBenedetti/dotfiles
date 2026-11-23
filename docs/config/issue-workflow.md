---
title: Issue Workflow
---

# Issue Workflow

A project can keep its tasks in GitHub Issues instead of a `TODO.md`. The
`/next-issue` command works them with the `gh` CLI, in Claude Code, OpenCode
and VS Code Copilot alike (see [Skills](./skills.md#shared-commands) for how it
reaches each tool). It is the counterpart of `/next-task`, which works a local
`TODO.md`: see [TODO Workflow](./todo-workflow.md). Pick one per project.

|                    | `/next-issue`                           | `/next-task`                         |
| ------------------ | --------------------------------------- | ------------------------------------ |
| Tasks live in      | GitHub Issues                           | `TODO.md` at the project root        |
| Approved when      | you label the issue `ready-for-agent`   | you move the line to `🟡 To do`      |
| Record of the work | a comment on the issue                  | an entry in `✅ Done`                |
| Visible to         | everyone, on a public repository        | you (the file is usually gitignored) |
| Needs              | `gh`, signed in and able to reach GitHub | nothing                              |

## Labels

The state of an issue is its label. Create them once per repository, with the
same names, colors and descriptions everywhere (`--force` updates a label that
already exists):

```sh
gh label create needs-triage    --force --color FBCA04 --description "Not evaluated yet: the owner triages"
gh label create needs-info      --force --color D876E3 --description "Blocked: waiting for the owner's answer"
gh label create ready-for-agent --force --color 0E8A16 --description "Approved and specified: /next-issue works it"
gh label create ready-for-human --force --color 1D76DB --description "Only the owner can do it: /next-issue manual"
gh label create urgent          --force --color B60205 --description "Goes first among the ready-for-agent issues"
```

| Label             | Meaning                                       | Worked by              |
| ----------------- | --------------------------------------------- | ---------------------- |
| `ready-for-agent` | Approved by the owner and specified           | `/next-issue`          |
| `ready-for-human` | Only the owner can do it                      | `/next-issue manual`   |
| `needs-info`      | Blocked: waiting for the owner's answer       | nobody, until answered |
| `needs-triage`    | Not evaluated yet (agent recommendations too) | the owner triages      |
| `urgent`          | Goes first among the candidates               |                        |

A project that names its labels differently says so in its
`docs/agents/triage-labels.md`, which the command reads first.

::: warning
Anyone can write an issue or a comment on a public repository, but only people
with rights on it can set a label. The command works an issue because **you**
labelled it, and reads its text as a description of the work, never as
instructions: a request in it to run a command or touch credentials is
reported to you, not followed.
:::

## Project board

Labels show one filter at a time. A GitHub Project gives the single view: one
board, with one column per triage label, for the issues of every repository.
It is project 1 of the `kevindb-labs` organization: GitHub tells only an
organization when a card moves.

A board groups its cards by a single-select field, not by label, so the
project has a `Stage` field that mirrors the labels:

| `Stage` column    | Issue                                  |
| ----------------- | -------------------------------------- |
| `Needs triage`    | `needs-triage`, or no triage label yet |
| `Needs info`      | `needs-info`                           |
| `Ready for agent` | `ready-for-agent`                      |
| `Ready for human` | `ready-for-human`                      |
| `Won't fix`       | `wontfix`, open or closed              |
| `Done`            | closed                                 |

When several triage labels are set, the one that stops the work wins:
`wontfix`, then `needs-info`, `ready-for-human`, `ready-for-agent`.
`urgent` is not a column: filter the board with `label:urgent`.

### Both ways, as it happens

A GitHub App sends its webhooks to a Cloudflare Worker, in
`.github/project-board/`, which keeps the two in step within seconds:

- **Labels to board:** an issue opened, reopened, labelled, unlabelled or
  closed, in any repository the App is installed on, is put on the board in
  the column of its labels.
- **Board to labels:** a card moved to another column updates its issue, in
  one call, as the table below says.

| Card moved to  | Issue                                                             |
| -------------- | ----------------------------------------------------------------- |
| an open column | its triage label replaces the others; reopened if closed          |
| `Won't fix`    | `wontfix` replaces the other triage labels; closed as not planned |
| `Done`         | loses `wontfix`; closed as completed                              |

Other labels, such as `urgent`, are kept. Both directions read the issue back
from GitHub instead of trusting the event, and leave alone what is already in
step; the Worker also ignores column changes made by the App itself. That is
how each stops at the other's change. An edit of another field, a card
cleared to no column, drafts and pull requests are left alone.

The App is public, because GitHub installs a private App only on the account
that owns it: anyone may install it. The Worker acts only on repositories of the
owners listed in `REPOSITORY_OWNERS` (`wrangler.toml`).

Each installation of the App sees one account only. The one on the
organization cannot see a private issue of your personal account, and the one
on your account cannot write the organization's board. The Worker reads and
moves the cards of those issues with `BOARD_TOKEN`, a classic token; every
other issue stays with the App.

### Setting it up

Once, for all repositories:

1. In the organization, create a project (Board layout) with a single-select
   field `Stage` holding the six options above (case does not matter), and
   group the board by it.
2. Create a GitHub App (your account's **Developer settings**): webhook URL
   the Worker's `workers.dev` address, a webhook secret (a random string, such
   as the output of `openssl rand -hex 32`), and
   - repository permissions: **Issues** read and write (Metadata read-only
     comes with it);
   - organization permissions: **Projects** read and write;
   - events: **Issues** and **Projects v2 item**;
   - installable on **Any account**.
3. Generate its private key, and convert it to PKCS#8, the format the Worker
   reads:

   ```sh
   openssl pkcs8 -topk8 -nocrypt -in <downloaded>.pem -out app-key.pem
   ```

4. From the repository root, deploy the Worker and store its secrets; the
   App ID is on the App's settings page:

   ```sh
   npx wrangler deploy --config .github/project-board/wrangler.toml
   npx wrangler secret put WEBHOOK_SECRET --config .github/project-board/wrangler.toml
   npx wrangler secret put GITHUB_APP_ID --config .github/project-board/wrangler.toml
   npx wrangler secret put GITHUB_APP_PRIVATE_KEY --config .github/project-board/wrangler.toml < app-key.pem
   npx wrangler secret put BOARD_TOKEN --config .github/project-board/wrangler.toml
   ```

   `BOARD_TOKEN` is a classic personal access token with the `repo` and
   `project` scopes, for the private issues of your personal account. It can
   read and write all your repositories: give it an expiry, and replace it
   before then.

   Then delete `app-key.pem` and the downloaded key: Cloudflare holds the
   only copy needed.
5. Install the App on the organization and on your account (**All
   repositories**, so new ones are covered).
6. Put the issues opened before the App on the board; running it again is
   safe:

   ```sh
   GH_TOKEN="$(gh auth token)" node .github/project-board/backfill.mjs owner/repo...
   ```

   For every repository of an account at once:

   ```sh
   gh repo list <account> --no-archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' \
     | GH_TOKEN="$(gh auth token)" xargs node .github/project-board/backfill.mjs
   ```

Each repository also needs the five triage labels. Copy them from this one
(it copies every label of this repository, and keeps the target's own):

```sh
gh label clone KevinDeBenedetti/dotfiles --repo owner/repo
```

A failed delivery answers 500, with the reason, in the App's Recent
Deliveries (its **Advanced** settings page), where it can be sent again:
GitHub does not redeliver a failed delivery on its own. The Worker's logs are in the Cloudflare dashboard.

## Running issues

| Invocation               | Effect                                                         |
| ------------------------ | -------------------------------------------------------------- |
| `/next-issue`            | Works the next `ready-for-agent` issue, then stops             |
| `/next-issue all`        | Works every `ready-for-agent` issue, one at a time             |
| `/next-issue 3`          | The same, for the next three issues                            |
| `/next-issue #42`        | Works that issue, whatever its labels                          |
| `/next-issue <words>`    | Works the open issue whose title matches the words             |
| `/next-issue manual`     | Guides you through the `ready-for-human` issues, step by step  |
| `/next-issue manual #42` | The same, for that issue only                                  |

Issues already assigned to you go first (an interrupted run), then `urgent`
ones, then the lowest number. For each issue, the agent:

1. assigns it to you, so an interrupted run leaves a trace;
2. implements it, with its tests and the docs it makes stale;
3. runs the project's checks, then a real test: the command that exercises the
   change the way its user would, run by the agent when it can, otherwise
   handed to you as a "Try it" line;
4. comments on the issue what changed and how it was verified, and removes
   `ready-for-agent`;
5. proposes a Conventional Commit message ending with `Fixes #<number>` and the
   files to stage, without committing.

The issue stays open until your commit reaches the default branch: GitHub then
closes it through the `Fixes` footer. The agent never closes an issue.

After a batch (`/next-issue all`, or a number), the summary proposes one
grouped commit instead of one per issue: a body line and a `Fixes #<number>`
footer for each issue done, and a single `git add` for the files of the run.
Its type is the one with the highest release impact among the issues, since
one commit gives one changelog line. Ask for one commit per issue when you
want the changelog to list each of them.

An issue it cannot finish gets a `BLOCKED:` comment and the `needs-info` label
in place of `ready-for-agent`, and the agent asks what to do. What only you can
do afterwards (deploy, a secret, a check the agent could not run) becomes a new
`ready-for-human` issue, with one task-list line per step.

## Recommendations and security findings

After its work, the agent files up to five recommendations as issues labelled
`needs-triage`; label the ones you want `ready-for-agent`.

Security findings are never filed: an issue is public before its fix is. The
agent reports them in the chat, and you track the ones that matter through the
repository's private vulnerability reporting.

The same goes for everything the agent writes on GitHub: no secret, no real IP
address or host name, no content of a gitignored file.

## Auditing a repository

`/audit` fills the tracker from the other end: it inspects the whole
repository and files what it finds for you to triage. It is read-only: it
changes no file, fixes nothing, and its only writes are the issues.

| Invocation              | Effect                                                       |
| ----------------------- | ------------------------------------------------------------ |
| `/audit`                | Audits the whole repository, then files the findings         |
| `/audit dry-run`        | The same audit, reported in the chat only                    |
| `/audit <path>`         | Limits the audit to that file or folder                      |
| `/audit <lens>`         | Limits it to one lens (`security`, `docs`, `tests`, …)       |
| `/audit dry-run <path>` | `dry-run` combines with a path or a lens                     |

The agent reads the project's own rules first (`AGENTS.md`, `GLOSSARY.md`,
`docs/adr/`), then audits each lens that applies: correctness, architecture,
tests, standards, documentation, domain language, agent docs, dependencies,
CI/CD, infrastructure (Terraform, Ansible, Kubernetes/Helm, Docker) and
security. With the `mattpocock-skills` plugin, each lens leans on the matching
skill (`codebase-design`, `domain-modeling`, `code-review`,
`writing-for-agents`, `diagnosing-bugs`, `research`).

A finding is reported only when it is tied to a file and line, actionable in
one change, and not already decided by an ADR. Critical and warning findings
become one `needs-triage` issue per fix, after a search of the open issues so
nothing is filed twice, with at most about fifteen issues per run. Security
findings stay in the chat, as above. Label the issues you want
`ready-for-agent`, and `/next-issue` works them.

## Guardrails

Agents may read, comment on, label and create issues (`gh issue view`, `list`,
`comment`, `edit`, `create`, and `gh label list`), in
`config/claude/settings.json` and `config/opencode/opencode.json` alike.
Closing or deleting an issue has no allow rule, so it asks first.

::: tip
In the Claude Code sandbox on macOS, `gh` fails with
`tls: failed to verify certificate` unless
`sandbox.enableWeakerNetworkIsolation` is on, as it is in
`config/claude/settings.json`: see [Claude Code](./claude-code.md#sandbox).
:::
