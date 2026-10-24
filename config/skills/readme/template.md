# README template

Exact section architecture — keep this order. Omit any optional section that
has nothing real to say; never omit a `[required]` one.

```markdown
# <Project name>
<!-- [required] Exact name from the project manifest (package.json "name",
     Cargo.toml [package] name, …), human-cased. -->

[![CI/CD](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/<repo>/<workflow>.yml?style=for-the-badge&label=CI%2FCD)](https://github.com/KevinDeBenedetti/<repo>/actions/workflows/<workflow>.yml) [![Release](https://img.shields.io/github/v/release/KevinDeBenedetti/<repo>?style=for-the-badge)](https://github.com/KevinDeBenedetti/<repo>/releases) [![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/KevinDeBenedetti/<repo>?style=for-the-badge&label=Scorecard)](https://scorecard.dev/viewer/?uri=github.com/KevinDeBenedetti/<repo>) [![License](https://img.shields.io/github/license/KevinDeBenedetti/<repo>?style=for-the-badge)](LICENSE)
<!-- One line, this order, each badge only when its condition holds (see
     SKILL.md "Badges"): CI/CD = a workflow file exists (copy its filename);
     Release = the repo publishes GitHub Releases; OpenSSF Scorecard = a
     workflow runs ossf/scorecard-action with `publish_results: true`;
     License = a LICENSE file exists. Never invent one. -->

> One sentence: what this project does and who it is for.
<!-- [required] No marketing fluff. Subject + verb + audience. -->

## Features
<!-- [required] 3–6 bullets: the most distinctive capabilities. No prose,
     no sub-bullets. Consistent style: start each with a verb or a noun. -->
- …

## Prerequisites
<!-- Only hard requirements to run the project. One bullet per tool with
     minimum version when it matters. Link the getting-started guide for
     the full setup instead of listing optional tools. -->
- …

## Installation
<!-- Optional — omit when setup is a single obvious command covered by
     Usage. Minimal steps, code blocks only, at most one comment per block. -->
```sh
…
```

## Usage
<!-- [required] One or two representative examples. Keep it short. -->
```sh
…
```

→ Full usage guide: [docs](<docs-url>)

## <Project-specific section>
<!-- 0–2 sections only this repo needs (Running in Docker, Git hooks,
     multi-account setup…). Place between Usage and Documentation.
     Keep each under 15 lines. -->

## Documentation
<!-- [required if docs/ exists] Exact wording below, substituting the URL. -->
Full documentation is available at **<docs-url>**.
It is generated from the `docs/` directory and published automatically on push.

## Contributing
<!-- Only if CONTRIBUTING.md exists. One line linking it. -->
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security
<!-- Only if SECURITY.md exists (root, docs/ or .github/ — link the real
     path). One line: where to report a vulnerability. -->
To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License
<!-- Only if a LICENSE file exists — [required] for a public repository
     (see SKILL.md "Public repositories"). SPDX identifier + link. -->
<SPDX identifier> — see [LICENSE](LICENSE).
```
