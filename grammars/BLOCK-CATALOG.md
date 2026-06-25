# Block Catalog

All block types available in the skill runtime. Only blocks with an executor are executed by `run_pipeline()`; others are metadata-only or sink-only.

| block_type | purpose | has_executor | typical_inputs | typical_outputs | when_to_use |
|---|---|---|---|---|---|
| `datasource` | Declares a data source and its supported formats. Holds no data — actual file paths are injected at runtime via the `inputs` dict passed to `run_pipeline()`. | No (metadata only) | — | Referenced by ReadBlock via its block ID | Always — every pipeline starts here. One per source file. |
| `read` | Reads a file from a DataSource, maps columns via `columns_alias_map`, and emits a typed LazyFrame. | Yes | DataSource block ID | LazyFrame of typed, aliased columns | Always — placed immediately after DataSource. One per DataSource. |
| `select` | Computes derived columns via expressions and optionally filters rows. Passes through or transforms columns from its input. | Yes | Any block with a LazyFrame output | LazyFrame with the declared columns | When you need to derive new columns (parse UTR from narration, compute net, cast types) before Journal. |
| `join` | Joins two LazyFrames on key expressions. References `left_id` and `right_id` instead of a single `input`. | Yes | Two upstream blocks (left + right) | LazyFrame of joined rows | When combining two source files into one row before journalizing (e.g. matching PO headers to lines). |
| `groupby` | Groups rows by key columns and applies aggregate expressions. Collapses multiple rows to one per group. | Yes | Any upstream LazyFrame | LazyFrame with one row per group + aggregated columns | When the source has multiple rows per business event (ERP voucher lines, ledger entries). Place between Read and Journal. |
| `union` | Vertically stacks multiple LazyFrames with compatible schemas. Takes a list of input IDs (`input_ids`). | Yes | Two or more upstream blocks | LazyFrame of stacked rows | When combining rows from multiple files of the same shape (e.g. monthly bank statements) before journalizing. |
| `journal` | Terminal sink block. Validates each row and emits two outputs: `journals_df` (header) and `entries_df` (DR/CR legs). Cannot be used as input to other blocks. | Yes | Any upstream LazyFrame | `(journals_df, entries_df)` via `JournalExecutionResult` | Always — exactly one per pipeline; must be the terminal node. |
| `write` | Writes a LazyFrame to a destination. | No executor in skill runtime | Any upstream LazyFrame | Persisted file/table | Not supported in skill configs. The skill runtime skips write blocks silently. Do not use in skill-authored configs. |
| `flow` | Legacy block type (pre-Journal). Predecessor to JournalBlock. | No executor in skill runtime | — | — | Do not use. Use `journal` instead. |
| `lookup` | Enriches rows by looking up values from a reference table. | No executor in skill runtime | Any upstream LazyFrame + reference | LazyFrame with joined lookup fields | Not supported in skill configs. The runtime skips lookup blocks silently. Wire separately if needed. |

---

## Executor availability summary

The skill runtime (`recon_lab/sources/runtime.py`) has executors registered for:

```
read, select, join, groupby, union, journal
```

Blocks without an executor in the skill runtime — `datasource`, `write`, `flow`, `lookup` — are either skipped silently or treated as metadata. Do not author configs that depend on `write` or `lookup` producing output LazyFrames; downstream blocks referencing their IDs will fail with a missing-frame error.

---

## Standard pipeline shapes

**Minimal (one file → journals):**
```
datasource → read → journal
```

**With column derivation:**
```
datasource → read → select → journal
```

**With row grouping (multi-row vouchers):**
```
datasource → read → groupby → journal
```

**With both:**
```
datasource → read → select → groupby → journal
```

**Multi-file union:**
```
datasource_a → read_a ─┐
                        ├─ union → journal
datasource_b → read_b ─┘
```
