---
name: docs-hub
description: Create, update, or audit the docs/ folder of a repository so it publishes correctly on the kevindebenedetti.github.io documentation hub (frontmatter, page layout, sidebar order, relative links). Use when adding, editing, moving, or reviewing any Markdown file under docs/, or when a code or config change requires its documentation to be updated.
---

# Documentation under `docs/` (kevindebenedetti.github.io hub)

Every public repository of the owner with a `docs/` folder is published on
`https://kevindebenedetti.github.io/<repo-name>/` by the hub repo
`KevinDeBenedetti/kevindebenedetti.github.io`. This skill is the contract
between a repo's `docs/` and that hub. The `README.md` is handled by the
`readme` skill; it only links here.

## How the hub consumes `docs/`

- A scheduled job (every 12 h) sparse-clones `docs/` of each public repo and
  copies it as-is to `synced/<repo-name>/`. There is **nothing to register**
  and no config file to add: having a `docs/` folder is the opt-in.
- Nav entry, sidebar and homepage card are **generated** from the file tree.
  The repo description on GitHub becomes the card description.
- A page's sidebar title is its frontmatter `title:`, else its first `# H1`,
  else the humanised filename.
- Sidebar order is not configurable: `index.md` first (labelled *Overview*),
  then files alphabetically, then sub-directories (titled from the folder name,
  `kebab-case` → `Title Case`, collapsed). Use file and folder names to steer
  the order.
- `docs/index.md` is optional. When absent the hub generates one listing every
  page. Add one only when the landing page needs real content.
- Hidden files and non-Markdown files are not in the sidebar.
- Each page gets an "edit on GitHub" link back to its file in the source repo.

## Rules

- Edit docs **in the source repo only**. Never edit the hub's `synced/`,
  `docs/index.md`, or `.vitepress/config.generated.ts` (all generated).
- One topic per page, kebab-case filename, grouped in folders by theme
  (e.g. `setup/`, `config/`, `guides/`). Keep `getting-started.md` at the
  root as the entry point.
- Every page starts with frontmatter and an H1 that match:

  ```markdown
  ---
  title: Agent Skills
  ---

  # Agent Skills
  ```

- Links between pages are **relative and end in `.md`** (`./skills.md`,
  `../setup/macos.md`). They must never escape `docs/` (the `check-docs-links`
  hook enforces it). External links are absolute URLs.
- Tables: padded/aligned pipes. Callouts: VitePress containers
  (`::: tip`, `::: warning`, `::: danger`) with a closing `:::`.
- Fenced code blocks always carry a language (`sh`, `json`, `yaml`, …).
- Document only facts verified in the repo (files, scripts, Makefile targets,
  config keys). Never invent a command, path, or option.
- English, ATX headings, no heading level skipped, no trailing whitespace.
- Do not duplicate the README: the README stays short and links to the docs.

## Steps

### 1 — Inventory

1. List `docs/` and read the pages touching the change (or all of them for an
   audit).
2. Identify which pages the change makes stale: new/renamed/removed files,
   commands, flags, config keys, install paths, tables of "existing X".
3. Check whether a page already covers the topic before creating a new one.

### 2 — Write

- Update the existing page in place when the topic exists; create a page (and
  folder) only for a genuinely new topic.
- When adding or removing a page, fix every inbound relative link and any
  index/overview table that lists pages.
- When moving a page, remember published URLs follow the path: grep the repo
  (README, other docs) for the old link.
- Keep the tone of the surrounding pages (reference vs. guide).

### 3 — Self-verify

- Frontmatter `title:` and H1 present and identical on every touched page.
- Every relative link resolves to an existing file inside `docs/`
  (`prek run check-docs-links --all-files` when prek is installed).
- Every command, path, and key quoted was read from the repo or run.
- README links still valid (`https://kevindebenedetti.github.io/<repo-name>/…`
  matches the page paths; no `.md` suffix in published URLs).
- Resulting commit type: `docs: …` (see the `commit-types` skill). Do not
  commit — the owner does it.

## Preview

The site is built in the hub repo (`bun run dev` there syncs from GitHub, so
only **pushed** docs show up). Locally, rely on the link check and on reading
the Markdown; do not try to publish from the source repo.
