# recon-authoring skill

Produces two things from raw transaction files (bank statements, ERP exports,
invoice CSVs):

1. A block-JSON config that runs through the `openrecon ingest` Blocks pipeline
   to emit reconciliation-ready journal records.
2. A YAML recon config that matches those journals across sources via the
   `openrecon run` match engine.

The skill runtime is the [`openrecon`](https://github.com/slainai/openrecon-rs)
binary — a single self-contained Rust executable, bundled (xz-compressed) at the
plugin root under `bin/` and installed by `scripts/install-openrecon.sh`. No
Python, no login, no network: authoring is entirely local. `openrecon` is one of
two conformant implementations of the OpenRecon spec; the platform's
Python/PySpark engine is the other. The same config file you validate and run
here is what you later deploy to a live tenant via the `numberlabs-configs`
skill.

`SKILL.md` next to this file is the canonical entry point — invocation
conditions, modes, CLI reference, and failure guide all live there. This README
is operator-facing notes for refreshing the bundled binaries.

---

## Where things live

The skill is one file (`SKILL.md`); its supporting assets sit at the plugin
root, not inside the skill directory:

```
${CLAUDE_PLUGIN_ROOT}/
  skills/recon-authoring/
    SKILL.md                    skill entry point
    README.md                   this file
  grammars/
    JOURNAL.md                  block-JSON authoring reference (Task A)
    RECON.md                    recon YAML grammar (Task B)
    EXPRESSIONS.md              expression DSL — all operators, examples
    BLOCK-CATALOG.md            block types, executor availability, pipeline shapes
  examples/
    journal-configs/            annotated journal configs
    recon-configs/              annotated recon configs
  scripts/
    install-openrecon.sh        installs the bundled openrecon binary (default: offline)
    refresh-bundled-openrecon.sh  maintainer: refresh bin/ from a release
  bin/
    openrecon-<unix-target>.xz           xz-compressed unix binaries (committed)
    openrecon-x86_64-pc-windows-msvc.zip Windows release zip, committed as-is
```

Skill content references all of these via `${CLAUDE_PLUGIN_ROOT}/...` paths.

---

## Deeper reading

| Grammar | What it covers |
|---|---|
| `grammars/JOURNAL.md` | DAG shape, DataSource/Read/GroupBy/Select/Journal args, validation layers, three authoring patterns |
| `grammars/RECON.md` | Full ReconUnit YAML grammar, field path DSL, all strategies, criteria, validation rules, resolution actions |
| `grammars/EXPRESSIONS.md` | All expression operators with dict shapes, common patterns, alias table |
| `grammars/BLOCK-CATALOG.md` | One-page block reference — what each block does and whether it has a runtime executor |

---

## Refreshing the bundled binaries

The plugin ships one compressed `openrecon` binary per target under `bin/` —
unix targets as `.xz`, the Windows target as its release `.zip`. When a new
`openrecon` release is cut in
[`slainai/openrecon-rs`](https://github.com/slainai/openrecon-rs), refresh them:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/refresh-bundled-openrecon.sh v0.1.0
```

For unix targets this downloads each release archive, verifies its checksum, and
re-compresses the binary to `bin/openrecon-<target>.xz`. The Windows target
(`x86_64-pc-windows-msvc`) is downloaded, checksum-verified, and committed as the
`bin/openrecon-x86_64-pc-windows-msvc.zip` release artifact unchanged — `.zip` is
native on Windows, so no `xz` is needed there. The Windows binary is built
out-of-band by the manual workflow in the openrecon-rs repo
(`gh workflow run windows-build.yml -f tag=v0.1.0`) and is only present once that
workflow has run for the tag; the refresh script skips it with a warning
otherwise. Commit the updated `bin/` archives under a `feat:`/`fix:` PR so
semantic-release cuts a plugin release. See the top-level README for the full
distribution flow.

The binaries are large (~200 MB uncompressed, polars + deltalake statically
linked), so they are committed compressed and decompressed on install. `xz` is
required at install time (standard on macOS/Linux).

---

## Known limits

These reflect the `openrecon` local binary; the platform's PySpark engine
relaxes some of them (distributed execution, production storage).

- **In-memory only.** The Blocks pipeline collects data into memory via polars.
  Files that exceed available RAM will OOM — there is no streaming path.
- **No production storage.** Local runs write parquet/JSON to the workspace, not
  Delta tables, MongoDB, or Postgres. Persisting to the platform happens only
  after you deploy the config to a live tenant.
- **No stream sources.** DataSource `source_type: stream` is schema-valid but has
  no local executor.
- **Single JournalBlock terminal.** Exactly one terminal JournalBlock per
  pipeline; multiple journal outputs are not supported.

For the authoritative executor-availability matrix, see
`grammars/BLOCK-CATALOG.md`.
