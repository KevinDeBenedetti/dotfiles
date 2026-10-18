---
name: readme
description: Generate or update a repository README.md following the standard architecture - CI badge, one-line tagline, features, prerequisites, usage examples, and a link to the unified docs site. Use when creating, rewriting, restructuring, or auditing a project README.
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
- Never invent a badge: include one only if a workflow file exists.

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
- `LICENSE` — license identifier (MIT, Apache-2.0, …)
- `CONTRIBUTING.md` — whether a Contributing section is warranted
- Existing `README.md` — sections worth preserving as-is

### 2 — Resolve the docs URL

If a `docs/` directory exists, the project's docs live at:

```
https://kevindebenedetti.github.io/<repo-name>/
```

Use that URL for every "→ full docs" link. If `docs/` does not exist, omit the
Documentation section entirely and drop the deep-link after Usage.

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
- The badge URL is real — workflow filename copied from an existing
  `.github/workflows/` file, not invented.
- Every linked path (`CONTRIBUTING.md`, `LICENSE`, `docs/`) exists in the repo.
- Every command shown was verified — run it, or read it in a script or Makefile.
- The docs URL matches the `<repo-name>` of this repository.
- File is **≤ 150 lines**.
- No section exceeds what is needed — prefer a link over inline prose.
- Conventional Commits type for the resulting commit: `docs: …`.
