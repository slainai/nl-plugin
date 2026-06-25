---
name: recon-authoring
description: Author block-JSON and YAML recon configs from Excel/CSV transaction data and validate/run them locally with the openrecon CLI. Emits balanced journals and matches across sources. Trigger on journal, recon, matching, DR/CR, balanced, bank, ERP, invoice, openrecon, blocks DSL, expression DSL, .xlsx, CSV, validate config, ingest, run match.
allowed-tools:
  - Read(${CLAUDE_PLUGIN_ROOT}/grammars/*)
  - Read(${CLAUDE_PLUGIN_ROOT}/examples/**)
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh:*)
  - Bash(openrecon:*)
  - Bash(openrecon validate:*)
  - Bash(openrecon ingest:*)
  - Bash(openrecon run:*)
  - Bash(openrecon spec:*)
---

# recon-authoring skill

This skill covers **local-only** config authoring, validation, and dry-run
execution with the `openrecon` CLI — a single self-contained binary, no Python,
no login, no network. It does not cover submitting anything to a live
numberlabs tenant — use the `numberlabs-configs` skill (which drives the Flow
Service API MCP server) for that.

`openrecon` and the platform's Python/PySpark engine are two conformant
implementations of the same OpenRecon spec (currently `v0.2.0`): the config you
validate and run locally here is the exact same file you later deploy to the
platform.

## What this skill produces

**Task A** — block-JSON config consumed by `openrecon ingest`.
Emits two canonical JSON files: `journals.json` (headers) and `entries.json`
(flat DR/CR rows), plus parquet sidecars. Every journal block declares a
required `pool` label — the identity namespace recon sides anchor on.

**Task B** — YAML `ReconUnit` config consumed by `openrecon run`.
Matches the journals Task A emitted across pools. Emits `result.json` with
matches, unclaimed, resolution items, and balance controls. Every side's `pick`
must contain a pool anchor (`field: pool`, op `equals`/`in`).

---

## Activation cues

Use this skill when the user says any of: journal, recon, matching, DR/CR,
balanced, bank reconciliation, ERP, invoice, openrecon, blocks DSL, expression
DSL, .xlsx, CSV — and the task is purely local (no mention of pushing to the
platform / a live tenant).

---

## Prerequisites

Install the bundled `openrecon` binary once per environment (decompresses the
binary committed under `bin/` — no network, no login):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh
openrecon --version          # → openrecon 0.1.0 (openrecon spec v0.2.0)
```

If `~/.local/bin` is not on `PATH`, either add it or invoke `openrecon` by full
path (`~/.local/bin/openrecon ...`). The binary needs no auth and no host
config — authoring is entirely offline.

The parenthetical in `--version` is the **config spec version** the binary
supports. Configs must pin this in their envelope (`openrecon: v0.2.0`).

---

## Invocation modes

| Mode | When to use | Pages to load |
|---|---|---|
| **journals-only** | User has one source file and only wants structured journal output | `${CLAUDE_PLUGIN_ROOT}/grammars/JOURNAL.md`, `${CLAUDE_PLUGIN_ROOT}/grammars/EXPRESSIONS.md`, `${CLAUDE_PLUGIN_ROOT}/grammars/BLOCK-CATALOG.md` |
| **recon-only** | User already has journals (from a prior run) and wants a matching config | `${CLAUDE_PLUGIN_ROOT}/grammars/RECON.md` |
| **full** | User has raw files and wants end-to-end journals + matching | All four grammars |

Load only the grammars you need. Each is self-contained.

---

## Canonical 6-step workflow

```
1. sample      — examine the file (headers, 5-10 rows, nullability)
                 use: head -5 file.csv  OR  a short polars/pandas python -c snippet
2. author      — write the block-JSON (Task A) or YAML (Task B) config
                 ALSO author an identifiers spec file alongside any blocks config:
                 identifiers.json = {"identifiers": ["utr", "invoice_no", ...]}
                 every key used in a journal block's `args.identifiers` and its
                 `args.primary_identifier` MUST appear in this list
                 BOTH Task A and Task B configs need the top-level envelope
                 `openrecon: v0.2.0` (validate rejects a config without it);
                 Task A: every journal block also needs a `pool` label (lowercase slug);
                 Task B: every side's `pick` needs a pool anchor on those labels
3. validate    — openrecon validate <config> --identifiers identifiers.json --format json
                 catches config-structure errors before execution; ALWAYS run this step
                 (--identifiers is required for blocks configs; match-only configs skip it)
4. execute     — openrecon ingest ... --identifiers identifiers.json  or  openrecon run ...
5. iterate     — read structured errors from stderr / result.json, fix, repeat
6. final       — deliver the config + identifiers spec + a brief summary of identifier/entry choices
```

Create a workspace once per session: `WORKDIR=$(mktemp -d -t recon-authoring-XXXXXX)`

### Multiple parallel streams → ONE config (default)

When a task spans several **parallel** business streams — e.g. Swiggy vs Zomato
orders, or each platform's bank-settlement recon — author **one** config with
one nested `recon_unit` per stream (`type: recon_unit`; see `RECON.md` §7b).
**Do not emit one file per stream.** Two reasons:

- **It's expressible in one unit.** Streams anchor on disjoint `pool` values,
  so the engine's claim-once consumption never cross-contaminates them — order
  between sibling streams is irrelevant.
- **Only one document is versioned downstream.** A recon config is published to
  the numberlabs platform (via the API server MCP) as a single versioned
  document (`match-config-document`); splitting streams across files means a
  later push captures only one of them and silently drops the rest. See the
  `numberlabs-configs` skill.

Name rules and sides uniquely per stream (`swiggy_aggregator`,
`zomato_aggregator`, …) — required for correct `match_id`s.

---

## CLI reference

### `openrecon validate <config-path> [--identifiers <spec.json>] [--format human|json]`

Parses and structurally validates a config without running it. Always run before
`ingest` or `run`. Exit `0`=valid, `2`=invalid (issues reported). With
`--format json` it emits a machine-readable report:
`{"ok": false, "issues": [{"path", "code", "message", "severity"}]}`.

`--identifiers <spec.json>` is **required when validating a blocks config** (any
config with a top-level `blocks` key). Match-only YAML configs don't take this
flag. The spec is a flat list: `{"identifiers": ["utr", "invoice_no", ...]}`.
Every identifier key referenced by a journal block — `args.identifiers` keys
plus `args.primary_identifier` — must be a subset of the declared list; otherwise
validation fails with a subset error.

### `openrecon ingest <config> --input NAME=PATH [...] --out DIR --identifiers <spec.json> [--run-id UUID] [--format text|json]`

Runs the Blocks pipeline; writes `journals.parquet` + `entries.parquet` and
their `journals.json` + `entries.json` sidecars to `DIR`, plus
`failures.<block-id>.parquet` for any block that produced failures. `NAME`
matches `args.name` of a `datasource` block. Input format auto-detected from
extension (`.csv`, `.tsv`, `.json`, `.jsonl`, `.parquet`, `.xlsx`/`.xls` →
excel). Exit `0`=success, `2`=invalid config (incl. undeclared identifier or a
match-only config), `3`=input file not found, `4`=runtime error.

`--identifiers <spec.json>` is **mandatory** for ingest, with the same subset
rule as validate.

Point `--out` at a fresh or empty directory per run (a per-session `$WORKDIR` is
the safe default) so each run starts clean.

```bash
openrecon ingest pipeline.json \
  --identifiers identifiers.json \
  --input bank_source=./data/bank.xlsx \
  --input erp_source=./data/erp.csv \
  --out "$WORKDIR"
```

### `openrecon run <config> (--journals DIR | --input NAME=PATH ...) --out DIR [--run-id UUID] [--as-of TS] [--format text|json]`

Runs the match engine and writes `result.json` plus ledger files. Two modes:

- **Combined** (config has both `blocks:` and `match:`): pass `--input` to
  ingest + match + write the ledger in one pass.
- **Conformance / match-only** (config has `match:` only, or you already ran
  `ingest`): pass `--journals DIR` — the output directory of a prior `ingest`
  (reads `journals.json` + `entries.json`, or the parquet files).

`--input` and `--journals` are mutually exclusive. `run` does **not** take
`--identifiers`. Exit `0`=all matched, **`1`=unclaimed journals present (NOT an
error — inspect result.json)**, `2`=invalid config, `3`=file not found,
`4`=runtime error.

```bash
openrecon run match.yaml \
  --journals "$WORKDIR" \
  --out      "$WORKDIR/results"
```

### Full pipeline (ingest then match)

```bash
openrecon ingest pipeline.json --identifiers identifiers.json \
  --input bank_source=./bank.xlsx --out "$WORKDIR" \
  && openrecon run match.yaml \
       --journals "$WORKDIR" \
       --out "$WORKDIR/results"
```

### `openrecon spec`

Prints the absolute paths to the installed OpenRecon SPEC.md files — the
normative reference for the spec version your binary supports. Exit `0`=printed,
`3`=no SPEC.md found (set `OPENRECON_SPEC_DIR` to a checkout's `spec/openrecon`).

---

## Where things live

| Path | Contents |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/grammars/JOURNAL.md` | block-JSON authoring reference |
| `${CLAUDE_PLUGIN_ROOT}/grammars/RECON.md` | recon YAML grammar |
| `${CLAUDE_PLUGIN_ROOT}/grammars/EXPRESSIONS.md` | expression DSL reference |
| `${CLAUDE_PLUGIN_ROOT}/grammars/BLOCK-CATALOG.md` | all blocks + executor availability |
| `${CLAUDE_PLUGIN_ROOT}/examples/` | annotated example configs |
| `${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh` | installs the bundled openrecon binary |

---

## Failure modes

| Issue code / symptom | Cause | Fix |
|---|---|---|
| `Invalid block ID` | Block ID is not a valid UUID | `python -c "import uuid; print(uuid.uuid4())"` |
| `parent scope` | Expression references non-`parent` table | Set all `col_ref` table values to `"parent"` |
| `Must be a column reference` | `identifiers` or `raw` contains a computed expression | Replace with a plain `col_ref`; use SelectBlock upstream |
| `--identifiers <path> is required` / journal identifier not in declared spec | Missing identifiers spec, or a journal block uses an identifier key (or `primary_identifier`) not listed in the spec | Author/extend `identifiers.json` so the declared list is a superset of every key used across journal blocks |
| `E_EMPTY_SIDE` | One DR/CR side is empty | Add at least one entry to both `debit_entries` and `credit_entries` |
| `No terminal JournalBlock found` | Pipeline missing or mismatched `journal` block | Confirm the last block's `type` is `"journal"` |
| pool missing/invalid on a journal block | `pool` is required and must match `^[a-z0-9_-]{1,64}$` | Add a lowercase-slug `pool` to the journal block's args (simplest: `pool` = `source`) |
| `side 'X' must scope by pool` | A match side's `pick` lacks a pool anchor | Add `- field: pool, op: equals, value: <pool_label>` as the first pick filter; keep `source` only as a refinement |
| `version_mismatch` (`Config pins openrecon spec 'v0.1.0' ...`) | Envelope version doesn't match the binary's spec version | Set `openrecon: v0.2.0` (check `openrecon --version` for the supported spec) |
| `unsupported file format 'X'` | Format outside `csv, tsv, json, jsonl, parquet, excel` | Use a supported format; `.xls` and `.xlsx` both go under `excel` |
| `JournalIdCollisionError` | Two differing rows in one batch produced the same `journal_id` — dedup key underspecified for the pool | Widen the read block's `dedup_columns`, or split the streams into distinct pools |
| `between references undeclared side` | `MatchCriterion.between` names an unknown side | Fix side name to match a declared `name` in `sides` |
| `Unbalanced journal` | `sum(DR) != sum(CR)` per row | Check amounts; add a balancing entry or use `abs(A - B)` pattern |
| `Extra inputs are not permitted` on `id_expr` | `id_expr` no longer exists — `journal_id` is system-derived from `dedup_columns` + `pool` | Remove `id_expr`; control identity via the read block's `dedup_columns` |
| `Field required` on `dedup_columns` / entry `currency` | Read blocks require `dedup_columns`; every entry requires a `currency` expression | Add `dedup_columns` (source-row identity columns) and a `currency` literal per entry |
| `file_scoped` requires non-empty `file_identity_columns` | `dedup_mode: "file_scoped"` needs file fingerprint columns; declaring them in other modes is rejected | Add `file_identity_columns` naming a constant-per-file column; drop the legacy `enable_dedup` key when using `dedup_mode` — see JOURNAL.md "Choosing a dedup mode" |
| `file_identity_columns column ... constant within one file` | A `file_scoped` fingerprint column varies per row, is null, or doesn't exist after alias mapping | Point `file_identity_columns` at a true file-level value (batch ref/UTR from file content), not a row-level column |
| exit 1 from `run` | Unclaimed journals remain — recoverable | Inspect `result.json`.`unclaimed`; loosen tolerances or add identifier candidates |
