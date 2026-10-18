# README template

Exact section architecture — keep this order. Omit any optional section that
has nothing real to say; never omit a `[required]` one.

```markdown
# <Project name>
<!-- [required] Exact name from the project manifest (package.json "name",
     Cargo.toml [package] name, …), human-cased. -->

[![CI/CD](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/<repo>/<workflow>.yml?style=for-the-badge&label=CI%2FCD)](https://github.com/KevinDeBenedetti/<repo>/actions/workflows/<workflow>.yml)
<!-- Only if a workflow file exists. Copy the filename from
     .github/workflows/ — never invent one. -->

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

## License
<!-- Only if a LICENSE file exists. Identifier + link. -->
<License identifier> — see [LICENSE](LICENSE).
```
