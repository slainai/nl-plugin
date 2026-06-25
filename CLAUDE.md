# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Repository status

Active. The customer-facing numberlabs plugin: three skills, an 8-page concept
catalog, the bundled `openrecon` CLI binaries (source in the separate
`slainai/openrecon-rs` repo), and an `.mcp.json` connection to the platform's
Flow Service API MCP server.

## Architecture

A dual-target plugin (Claude Code + OpenCode) teaching an AI agent to
author/validate numberlabs reconciliation configs locally and drive them against
a live tenant. Two surfaces, do not confuse them:

- **Local authoring → the `openrecon` Rust binary.** A single self-contained
  executable (no Python, no login, no network). Verbs: `validate`, `ingest`,
  `run`, `spec`. Source lives in `slainai/openrecon-rs`; this repo ships only
  the prebuilt binaries, xz-compressed, under `bin/`. The `recon-authoring`
  skill owns this.
- **Live tenant → the Flow Service API MCP server** mounted at `/mcp`. A
  curated 64-tool surface (tool name = route `operationId`) grouped into six
  toolsets (`authoring`, `recon`, `actions`, `charts`, `reports`, `data`),
  trimmable per request via the `X-MCP-Toolsets` header. The `.mcp.json` bridges
  to it through `mcp-remote` (OAuth 2.1). The `numberlabs-configs` and
  `numberlabs-runtime` skills own this.

Decisions already made — do not relitigate without reason:

- **No CLI for live work.** The predecessor (`numberlabs-plugin`) shipped the
  `nlcloud` Rust CLI as transport; this repo replaces it with the platform's own
  MCP server. There is no `nlcloud` here.
- **No Python.** The predecessor shipped a `numberlabs` wheel for local
  validation; this repo replaces it with the `openrecon` binary. There is no
  `pip`, no wheel, no `requirements.txt`.
- **Customer voice, already-provisioned org.** Every MCP call is scoped to the
  signed-in user's existing org. There is **no** org-creation, org-user, or
  support-access surface here (the predecessor's `nlcloud-admin` skill and
  `ADMIN-SUPPORT-USERS.md` page were intentionally dropped — those are internal
  platform-operator concerns). Skills read as a customer using their own tenant.
- **Concept pages cover what the tool list can't.** `api/*.md` documents
  semantics the advertised MCP tool schemas don't express (state machines,
  optimistic-concurrency contract, deploy locks, action polling, chart
  materialization ordering, report SSE/template constraints). Exact tool names
  and request shapes come from `tools/list` at runtime.
- **`${CLAUDE_PLUGIN_ROOT}` everywhere** in SKILL.md `allowed-tools` and body
  references.

## Workflow conventions

- Every live submission is gated by a clean local `openrecon validate` before
  any MCP `submit`/`deploy`/`publish` tool call. Bake this ordering into
  SKILL.md when authoring.
- For configs with a top-level `blocks` key, `openrecon validate` and `ingest`
  require `--identifiers <spec.json>`; match-only YAML configs omit it.
- Refer to MCP tools by purpose + the route they wrap + their toolset — do not
  invent `operationId`s. Read the tool's input schema in the advertised list for
  the body shape.

## Binary distribution (important)

- The `openrecon` binaries are ~200 MB uncompressed (polars + deltalake +
  datafusion statically linked). GitHub hard-blocks files >100 MB, so they are
  committed compressed under `bin/` and expanded on install. Two formats by
  platform:
  - **unix** (`*-apple-darwin`, `*-unknown-linux-musl`) → `openrecon-<target>.xz`
    (~31–40 MB; xz is standard on mac/linux).
  - **Windows** (`x86_64-pc-windows-msvc`) → the release `openrecon-<target>.zip`
    committed **as-is**. zip is native on Windows (Expand-Archive / `tar -xf`)
    whereas xz is not installed there by default, so we avoid an xz dependency
    exactly where it hurts most.
  `.gitignore` keeps raw decompressed binaries out; only `bin/*.xz` and
  `bin/*.zip` are committed.
- `scripts/install-openrecon.sh` — default path expands the bundled archive for
  the current platform (xz-decompress on unix, unzip on Windows; offline,
  sandbox-safe); `--download` fetches from GitHub Releases via `gh` (`.tar.gz`
  on unix, `.zip` on Windows).
- `scripts/refresh-bundled-openrecon.sh <tag>` — maintainer tool: unix targets
  are downloaded, checksum-verified, and re-compressed to `.xz`; the Windows
  `.zip` is downloaded, checksum-verified, and committed as-is.
- **Windows** (`x86_64-pc-windows-msvc`) is the binary that lets Claude Cowork
  app sessions on Windows validate configs. It is built out-of-band by
  `slainai/openrecon-rs`'s manual `windows-build.yml` workflow
  (`workflow_dispatch` only — deliberately NOT in the release path), then pulled
  in by the refresh script. It is absent from a release until that workflow runs.

## Skill frontmatter rules

Claude Code skill frontmatter is strict. Allowed keys: `name`, `description`,
`allowed-tools`. Anything else breaks discovery.

`allowed-tools` mixes:
- `mcp__numberlabs` — grants the skill the MCP server's tools. (If the server's
  resolved name differs once installed, update this; a mismatch only triggers a
  permission prompt, it does not break the skill.)
- `Bash(openrecon validate:*)` etc. — verb-scoped local CLI access. Authoring
  skill allowlists `ingest`/`run` too; the config/runtime skills allowlist only
  `openrecon validate` (the local gate) plus the install script.
- `Read(${CLAUDE_PLUGIN_ROOT}/api/*)` / `Read(${CLAUDE_PLUGIN_ROOT}/grammars/*)`.

## Cross-repo source pointers

- `slainai/openrecon-rs` (`/Users/harsh/product/openrecon-rs`) — the `openrecon`
  CLI source + the OpenRecon spec (`spec/openrecon/`, currently `v0.2.0`).
  Clone there to `cargo build`/`cargo test`; its `release-plz` CI cuts `v*`
  releases. The manual Windows build workflow also lives there.
- `/Users/harsh/product/flow-service/` — the Flow Service API + MCP server
  source; ground truth for `api/*.md` and the MCP toolset/operationId surface.
- `/Users/harsh/product/product-docs/content/api/mcp.md` — the published MCP
  server docs `api/MCP.md` is derived from.
- `/Users/harsh/product/numberlabs-plugin/` — the predecessor (internal) plugin
  this one is adapted from. Historical reference for grammars/examples/api pages.

## Build / test

- No top-level build. `scripts/*.sh` run on macOS + Linux (bash 3.2 compatible).
- Smoke: `scripts/install-openrecon.sh && openrecon --version`.
- The `openrecon` source builds/tests in its own repo (`cargo build/test`).

## Contributing, releases, branch protection

See `CONTRIBUTING.md`. Conventional-Commit PR titles, squash-merge only,
automatic releases via `python-semantic-release` (config in `pyproject.toml`,
rewrites the `version` in BOTH manifests on push to `main`). **Never hand-edit**
the version in either manifest or `CHANGELOG.md`.
