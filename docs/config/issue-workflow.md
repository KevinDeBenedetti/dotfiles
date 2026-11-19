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

The state of an issue is its label. Create them once per repository:

```sh
gh label create ready-for-agent --description "Approved and specified for an agent"
gh label create ready-for-human --description "Only the owner can do it"
gh label create needs-info --description "Blocked: waiting for the owner"
gh label create needs-triage --description "Not evaluated yet"
gh label create urgent --description "Goes first"
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

## Guardrails

Agents may read, comment on, label and create issues (`gh issue view`, `list`,
`comment`, `edit`, `create`, and `gh label list`), in
`config/claude/settings.json` and `config/opencode/opencode.json` alike.
Closing or deleting an issue has no allow rule, so it asks first.

::: tip
In the Claude Code sandbox on macOS, `gh` can fail with
`tls: failed to verify certificate`. The
[sandboxing documentation](https://code.claude.com/docs/en/sandboxing) gives
the two settings that fix it, and what each one weakens.
:::
