# Contributing to the numberlabs plugin

This document is the source of truth for **how to land changes** in this repo.
Read it before opening a PR — especially if you are an AI agent. Most guardrails
below are enforced by CI and the `main` branch ruleset; breaking them blocks your
merge.

For *what the code does*, start with `README.md` and `CLAUDE.md`.

---

## TL;DR

1. Branch from `main` (`feat/<slug>` or `<user>/<issue>-<slug>`).
2. Open the PR with a **Conventional Commits**–formatted title — it becomes the
   squash commit subject and drives the version bump.
3. Squash-merge only (merge-commit and rebase are disabled).
4. Never touch the `version` field in `.claude-plugin/plugin.json` or
   `.claude-plugin/marketplace.json`, or `CHANGELOG.md`. Release automation owns
   all three.

---

## Commit / PR title format

```
<type>(<optional scope>): <short imperative summary>
```

| Type | Triggers release? | Use for |
|---|---|---|
| `feat` | **YES — minor bump** | New skill, new concept page, refreshed `openrecon` binary with new capability, expanded `allowed-tools`, new MCP toolset wiring |
| `fix` | **YES — patch bump** | Bug in a skill, a packaged script, a concept page that misdescribes behaviour, or a binary bug-fix refresh |
| `perf` | **YES — patch bump** | Speedup with identical behaviour |
| `refactor` | No | Internal restructure, identical external behaviour |
| `docs` | No | `README.md`, `CLAUDE.md`, `api/*.md`, `grammars/*`, this file |
| `test` | No | Test trees (the `openrecon` CLI has its own tests in `slainai/openrecon-rs`) |
| `chore` | No | Tooling, housekeeping, version-bot commits |
| `ci` | No | `.github/workflows/*`, ruleset edits, release plumbing |
| `build` | No | Build/packaging scripts, `pyproject.toml` non-version fields |
| `style` | No | Whitespace, formatting |

**Type vs scope:** the bump is driven by the **type** (word before `(scope):`),
not the scope. `fix(ci): ...` bumps a patch (type is `fix`); `ci(release): ...`
does not (type is `ci`).

While in 0.x, breaking changes (`feat!`) still only bump **minor** —
`major_on_zero = false` in `pyproject.toml`.

---

## Releases (automatic)

`python-semantic-release` config lives in `pyproject.toml` under
`[tool.semantic_release]`. On every push to `main`, the release workflow reads
commits since the last tag, rewrites the `version` field in BOTH
`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, regenerates
`CHANGELOG.md`, commits as `chore(release): X.Y.Z`, and tags `vX.Y.Z`.

**Never hand-edit** the version in either manifest, or `CHANGELOG.md`. Editing
one manifest but not the other silently breaks `/plugin update` for installed
users (the marketplace reads `marketplace.json`; the client compares against
`plugin.json`).

---

## Refreshing the bundled `openrecon` binaries

The `openrecon` CLI source is **not** in this repo — it lives in
[`slainai/openrecon-rs`](https://github.com/slainai/openrecon-rs) with its own
`release-plz` CI. This repo ships only the prebuilt, xz-compressed binaries under
`bin/`.

When a new `openrecon` release is cut:

```bash
scripts/refresh-bundled-openrecon.sh v0.1.0
```

This downloads each target's archive, verifies its checksum, and re-compresses
the binary to `bin/openrecon-<target>[.exe].xz`. Commit the updated `bin/*.xz`
under a `feat:` (new capability) or `fix:` (bug-fix) PR title so semantic-release
cuts a plugin release.

**Windows** (`x86_64-pc-windows-msvc`) is built out-of-band — it is intentionally
NOT in the openrecon-rs release path (to avoid adding build time). Build it first,
then refresh:

```bash
gh workflow run windows-build.yml -R slainai/openrecon-rs -f tag=v0.1.0
# wait for it to attach openrecon-x86_64-pc-windows-msvc.zip to the release, then:
scripts/refresh-bundled-openrecon.sh v0.1.0
```

Only `bin/*.xz` is committed; `.gitignore` keeps decompressed binaries out.
Binaries must stay under GitHub's 100 MB per-file limit — xz keeps them ~31–40 MB.

---

## What NOT to commit

- Raw (decompressed) `openrecon` binaries — only `bin/*.xz`.
- Any auth token or cached MCP credential. The `.mcp.json` carries no secrets;
  `mcp-remote` caches tokens outside the repo.
- The `version` field in either manifest, or `CHANGELOG.md` (release bot owns
  them).
