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

Labels show one filter at a time. A GitHub Project gives the single view: a
board with one column per triage label. This repository's board is project 1
of the `kevindb-labs` organization: GitHub tells only an organization when a
card moves, so a board owned by a user could follow the labels but not drive
them.

A board groups its cards by a single-select field, not by label, so the
project has a `Stage` field that mirrors the labels, in both directions:

- **Labels to board:** the `.github/workflows/project-stage.yml` workflow runs
  on every issue opened, reopened, labelled, unlabelled or closed. It adds the
  issue to the project (a new issue lands on the board without a manual step)
  and sets its `Stage`.
- **Board to labels:** moving a card to another column sets the issue's
  labels within seconds (see [below](#from-the-board-to-the-labels)).

| `Stage` column    | Issue                                                  |
| ----------------- | ------------------------------------------------------ |
| `Needs triage`    | `needs-triage`, or no triage label yet                 |
| `Needs info`      | `needs-info`                                           |
| `Ready for agent` | `ready-for-agent`                                      |
| `Ready for human` | `ready-for-human`                                      |
| `Won't fix`       | `wontfix`, open or closed                              |
| `Done`            | closed                                                 |

When several triage labels are set, the one that stops the work wins:
`wontfix`, then `needs-info`, `ready-for-human`, `ready-for-agent`.
`urgent` is not a column: filter the board with `label:urgent`.

Set it up once per repository:

1. Create a project (Board layout) in the organization and link it to the
   repository.
2. Add a single-select field `Stage` with the six options above (case does
   not matter), and group the board by it. A run that cannot find a column
   fails and lists the options the field has.
3. Create a classic personal access token with the `project` scope only, and
   store it as the `PROJECT_TOKEN` secret: `GITHUB_TOKEN` cannot write to a
   project.
4. Set the `PROJECT_OWNER` repository variable to the organization's login,
   and `PROJECT_NUMBER` to the number at the end of the project's URL. The
   workflow is skipped until `PROJECT_NUMBER` is set; without
   `PROJECT_OWNER`, it looks for the project under the repository's owner.
5. Run the workflow by hand once (`gh workflow run project-stage.yml`): a
   manual run puts every open issue on the board.

### From the board to the labels

A Cloudflare Worker, in `.github/project-board/`, receives the organization
webhook's `projects_v2_item` events: Actions cannot trigger on them. On a card
moved to another column, it reads the issue back from GitHub and updates it in
one call:

| Card moved to  | Issue                                                             |
| -------------- | ----------------------------------------------------------------- |
| an open column | its triage label replaces the others; reopened if closed          |
| `Won't fix`    | `wontfix` replaces the other triage labels; closed as not planned |
| `Done`         | loses `wontfix`; closed as completed                              |

Other labels, such as `urgent`, are kept. A card already in step with its
issue changes nothing: that is how the Worker and the workflow stop, when
each sees the other's change. An edit of another field, a card cleared to
no column, cards of other repositories, drafts and pull requests are left
alone.

Set it up once, after the board:

1. Create a classic personal access token with the `public_repo` and
   `read:project` scopes, for the Worker. Both tokens are classic: the
   organization must not restrict classic tokens (its **Personal access
   tokens** settings).
2. In `.github/project-board/`, check the `[vars]` of `wrangler.toml`, then
   deploy and store the two secrets (the webhook secret is a random string,
   such as the output of `openssl rand -hex 32`):

   ```sh
   npx wrangler deploy
   npx wrangler secret put GITHUB_TOKEN
   npx wrangler secret put WEBHOOK_SECRET
   ```

3. In the organization's settings, add a webhook: payload URL the Worker's
   `workers.dev` address, content type `application/json`, the same secret,
   and the **Project v2 items** event only. GitHub's first delivery is a ping,
   which the Worker answers with `pong`.

A failed update answers 500: the webhook's **Recent Deliveries** show it,
and it can be redelivered from there. The Worker's logs are in the Cloudflare
dashboard.

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
