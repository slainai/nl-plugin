# numberlabs plugin

A Claude Code / OpenCode plugin that lets an AI agent **author and validate**
numberlabs reconciliation configs locally with the `openrecon` CLI, then
**drive them against a live tenant** through the numberlabs platform's MCP
server — no internal tooling, no CLI to log into, no Python.

It is the customer-facing successor to the internal `numberlabs-plugin`: that
one shipped the `nlcloud` Rust CLI and the `numberlabs` Python wheel; this one
replaces the CLI transport with the platform's **Flow Service API MCP server**
and replaces the Python wheel with the **single prebuilt `openrecon` binary**.

## What it bundles

- **Three narrowly-scoped skills:**
  - `recon-authoring` — local-only authoring, validation, and dry-run execution
    of block-JSON / recon YAML with the `openrecon` binary.
  - `numberlabs-configs` — submit / publish / deploy configs to your live tenant
    via the MCP server's `authoring` toolset.
  - `numberlabs-runtime` — recon runs, actions (incl. sandbox), refresh, charts,
    and reports via the MCP server's `recon` / `actions` / `data` / `charts` /
    `reports` toolsets.
- **The `openrecon` CLI** — a single self-contained Rust binary (source in
  [`slainai/openrecon-rs`](https://github.com/slainai/openrecon-rs)). This repo
  ships only the prebuilt, xz-compressed binaries under `bin/`.
- **An MCP connection** — `.mcp.json` bridges to the deployment's `/mcp`
  endpoint through `mcp-remote` (OAuth 2.1).
- **8 concept-only API pages** under `api/` — what the advertised MCP tool list
  cannot express (toolsets, auth/OAuth, ingest lifecycle + concurrency, deploy
  locks, action polling, chart materialization ordering, report SSE/templates).
- **Spec grammars + annotated examples** under `grammars/` and `examples/`.

## Two surfaces, one config

```
Local (offline)                         Live tenant (MCP)
  openrecon validate config.yaml          numberlabs MCP server at /mcp
  openrecon ingest  ... --out ./out       authoring / recon / actions /
  openrecon run     ... --out ./out       charts / reports / data toolsets
```

`openrecon` and the platform's Python/PySpark engine are two conformant
implementations of the same OpenRecon spec (`v0.2.0`). The exact file you
validate and run locally is what you deploy to the tenant. **Every deploy is
gated by a clean local `openrecon validate` first.**

## Quickstart

```bash
# Install the plugin
/plugin marketplace add slainai/nl-plugin
/plugin install numberlabs@slainai

# Install the bundled openrecon binary (offline — decompresses bin/*.xz)
${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh
openrecon --version          # → openrecon 0.1.0 (openrecon spec v0.2.0)

# The MCP server connects automatically via .mcp.json on first live-tenant
# use; it runs an OAuth 2.1 browser sign-in to your org and caches the token.
```

Authoring is fully local and needs no auth. Live-tenant tools require the OAuth
sign-in; see `api/MCP.md` and `api/AUTH.md`.

## Why MCP instead of a CLI

The platform's REST surface is ~197 routes. The previous plugin avoided
exposing them as tools (context cost) by shipping a verb-based CLI. The platform
now solves that itself: the `/mcp` mount is **curated to 64 tools**, grouped into
six toolsets, and **trimmable per request** via the `X-MCP-Toolsets` header. So a
customer gets a focused, auth-correct tool surface with nothing to install or log
into for live work — the only local binary is `openrecon`, used purely for
offline authoring and validation.

## Layout

```
.claude-plugin/      Claude Code plugin manifests (name: numberlabs)
.mcp.json            MCP server connection (mcp-remote → /mcp, all 6 toolsets)
defaults.json        named environments (prod default, staging, local)
api/                 8 concept pages (MCP, auth, lifecycle, runtime semantics)
grammars/            block-JSON / recon YAML / expression DSL references
examples/            annotated config examples
bin/
  openrecon-<unix-target>.xz             xz-compressed unix binaries (committed)
  openrecon-x86_64-pc-windows-msvc.zip   Windows release zip, committed as-is
scripts/
  install-openrecon.sh           expand bundled binary → ~/.local/bin (offline)
  refresh-bundled-openrecon.sh   maintainer: refresh bin/ from a release
skills/
  recon-authoring/               local config authoring (openrecon)
  numberlabs-configs/            push configs to tenant (MCP authoring)
  numberlabs-runtime/            runs, actions, charts, reports (MCP)
```

## Distribution

The `openrecon` binaries are large (~200 MB uncompressed — polars + deltalake
statically linked), so they are committed compressed (well under GitHub's
per-file limit) and expanded by `install-openrecon.sh` on first use, keeping
install working offline inside a Cowork / Claude Code sandbox. Two formats by
platform:

- **unix** (macOS / Linux) → `openrecon-<target>.xz` (~31–40 MB). `xz` is
  required at install time (standard on macOS/Linux).
- **Windows** → the release `openrecon-x86_64-pc-windows-msvc.zip` committed
  **as-is**. `.zip` is native on Windows (Expand-Archive / `tar -xf`), so the
  Windows path needs no `xz` — the install script just unzips it.

When a new `openrecon` release is cut in
[`slainai/openrecon-rs`](https://github.com/slainai/openrecon-rs), refresh the
bundled binaries:

```bash
scripts/refresh-bundled-openrecon.sh v0.1.0   # unix → re-compress .xz; windows → commit .zip as-is
```

The Windows binary (`x86_64-pc-windows-msvc`) — the one that lets **Claude Cowork
app** sessions on Windows validate configs locally — is built out-of-band by a
manual workflow in the openrecon-rs repo (it is **not** in the normal release
path, to avoid adding build time):

```bash
gh workflow run windows-build.yml -R slainai/openrecon-rs -f tag=v0.1.0
# then refresh: scripts/refresh-bundled-openrecon.sh v0.1.0
```

Then commit the updated `bin/*.xz`. **Do not hand-edit the `version` field** in
`.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json` —
semantic-release rewrites both on every push to `main`. Land binary updates under
a `feat:` PR title (new CLI capability) or `fix:` (bug-fix release).

The plugin itself is distributed via `.claude-plugin/marketplace.json`, which
Claude Code reads from this repo's default branch on `/plugin install` /
`/plugin update`.

## Contributing & releases

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). Quick summary:

- PR titles follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `perf:`, `docs:`, `chore:`, `ci:`, …). Squash-merge only.
- `feat:` bumps minor, `fix:`/`perf:` bump patch, everything else no-release.
  While in 0.x, breaking changes still only bump minor.
- The release bot rewrites the `version` field in both manifests, writes
  `CHANGELOG.md`, tags `vX.Y.Z`, and publishes a GitHub Release on every push to
  `main`.
