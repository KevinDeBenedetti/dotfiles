---
name: readme
description: Generate or update a repository README.md following the standard architecture - badges (CI, release, OpenSSF Scorecard, license), one-line tagline, features, prerequisites, usage examples, a link to the unified docs site, and the security/license sections a public repository needs. Use when creating, rewriting, restructuring, or auditing a project README.
---

# Generate or update the repository `README.md`

You are writing or restructuring the `README.md` of the current repository.
Your goal is a **synthetic, scannable** file that lets any developer understand
the project at a glance and follow links to the full documentation — without
duplicating it inline.

Follow the exact section architecture defined in [`./template.md`](./template.md).

---

## Rules

- Only document facts you have **verified** by reading actual files in this repo.
- Do **not** hallucinate commands, paths, badges, or links that don't exist.
- Keep the output to **≤ 150 lines** of Markdown.
- Write in natural language, in **English**. Use ATX headings (`#`), blank
  lines between sections.
- **Do not repeat** content that lives in the docs site — link to it instead.
- If a section has nothing relevant to say, **omit it entirely**.
- Never invent a badge: include one only when its condition below holds.
- Link files of the repository with **relative** paths (`LICENSE`,
  `docs/…`): GitHub resolves them on every branch and they work in clones.

## Badges

One line under the title, in this order, all `style=for-the-badge` so they
render as one row. Include each badge only when its condition is **verified**:

| Badge             | Condition                                                                              |
| ----------------- | -------------------------------------------------------------------------------------- |
| CI/CD             | A workflow file exists — copy its filename from `.github/workflows/`                    |
| Release           | The repository publishes GitHub Releases (e.g. a release-please workflow, or `v*` tags) |
| OpenSSF Scorecard | A workflow runs `ossf/scorecard-action` with `publish_results: true` — without it the badge has no data |
| License           | A `LICENSE` file exists                                                                 |

The exact URLs are in [`./template.md`](./template.md). The Scorecard badge
links to the public report (`https://scorecard.dev/viewer/?uri=github.com/<owner>/<repo>`);
the project's upstream form is
`https://api.scorecard.dev/projects/github.com/<owner>/<repo>/badge` — use the
shields.io one for a consistent style. Never add vanity badges (stars,
downloads, "made with").

## Public repositories

Most of these projects are public: anyone can read the README, and GitHub's
**Community Standards** checklist (Insights → Community Standards) looks for
README, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY and issue templates.
For a public repository:

- **License is required.** Without a `LICENSE` file the code is not legally
  reusable. If it is missing, do not write a License section or badge: tell
  the owner and suggest one (MIT is the usual choice for these projects).
- Add the **Security** section when `SECURITY.md` exists, so vulnerability
  reports go to the private channel it describes, not to public issues.
- Add **Contributing** only when `CONTRIBUTING.md` exists.
- **Never publish infrastructure details**: no real IP addresses, host names,
  internal URLs, cluster or account names, secret names with values, or
  personal data. Use placeholders (`<host>`, `example.com`).
- Prerequisites name what a stranger needs (runtime versions, accounts, a
  self-hosted runner version…), not the owner's local setup.

Tell a public repository from a private one by the remote's visibility; when
it cannot be checked, apply these rules anyway — they cost nothing on a private
repository.

---

## Steps to follow

### 1 — Inventory the repository

Read and reason over each of the following **before writing anything**.

**Project manifest** (first one found wins):

- `package.json` / `bun.lock` — name, description, scripts
- `Cargo.toml` — `[package]` name and description
- `pyproject.toml` / `requirements.txt` — name and entry points
- `go.mod`, `Makefile` — module name, targets

**Tooling and CI**:

- `prek.toml` / `.pre-commit-config.yaml` — hooks and required tools
- `.github/workflows/*.yml` — badge URL and what the pipeline does
- `Dockerfile` / `docker-compose.yaml` — whether a Docker section is warranted

**Docs and metadata**:

- `docs/` — top-level pages available for deep-linking
- `LICENSE` — SPDX license identifier (MIT, Apache-2.0, …)
- `CONTRIBUTING.md` — whether a Contributing section is warranted
- `SECURITY.md` (root, `docs/` or `.github/`) — whether a Security section is warranted
- `.github/workflows/*scorecard*.yml` with `publish_results: true` — Scorecard badge
- GitHub Releases / `v*` tags, or a release-please config — Release badge
- Existing `README.md` — sections worth preserving as-is

### 2 — Resolve the docs URL

If a `docs/` directory exists, the project's docs live at:

```
https://kevindebenedetti.github.io/<repo-name>/
```

Use that URL for every "→ full docs" link. If `docs/` does not exist, omit the
Documentation section entirely and drop the deep-link after Usage.

The URL is the hub's: `docs/` is published by `kevindebenedetti.github.io`
under `/<repo-name>/`, and a page's path maps to its URL without the `.md`
suffix (`docs/getting-started.md` → `…/<repo-name>/getting-started`). Deep-link
only to pages that exist. Never copy docs content into the README; when the
task also requires creating or editing pages under `docs/`, follow the
`docs-hub` skill for them.

### 3 — Write the README

Produce `README.md` structured **exactly** as defined in
[`./template.md`](./template.md) — keep the section order.

When updating an existing README:

- Preserve any project-specific section that is still accurate
  (e.g. *Running in Docker*, *Git hooks*) — place it between Usage and
  Documentation.
- Rewrite anything that contradicts what you verified in step 1.
- Delete sections that duplicate the docs site verbatim.

### 4 — Self-verify

Before saving, confirm:

- The project name matches the manifest, human-cased.
- Every badge meets its condition in "Badges" — the CI workflow filename is
  copied from an existing `.github/workflows/` file, the Scorecard workflow
  has `publish_results: true`, releases or a LICENSE exist.
- Every linked path (`CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, `docs/`)
  exists in the repo, linked relatively.
- Public repository: a License section exists (or the owner was told the
  `LICENSE` file is missing), and no infrastructure detail appears.
- Every command shown was verified — run it, or read it in a script or Makefile.
- The docs URL matches the `<repo-name>` of this repository, and every
  deep-linked page exists as `docs/<path>.md`.
- Every relative link to a file under `docs/` or elsewhere in the repo resolves.
- File is **≤ 150 lines**.
- No section exceeds what is needed — prefer a link over inline prose.
- Conventional Commits type for the resulting commit: `docs: …`.
