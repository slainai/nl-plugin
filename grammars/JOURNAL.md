# Journal Block-JSON Grammar

How to author a block-JSON config that emits reconciliation-ready journal records.

---

## DAG shape

Every valid journal pipeline follows this structure:

```
DataSource → ReadBlock → [SelectBlock?] → [GroupByBlock?] → JournalBlock
```

Rules:
- `JournalBlock` is always the terminal (sink). Nothing reads from it.
- `SelectBlock` is optional — use it to derive new columns (parse UTR from narration, compute net amount, etc.).
- `GroupByBlock` is optional — use it when the source has multiple rows per business event (ERP voucher lines). It collapses them to one row before Journal sees them.
- All block IDs must be valid UUIDs.

---

## Top-level config shape

```json
{
  "openrecon": "v0.2.0",
  "blocks": [
    { "id": "<uuid>", "type": "datasource", "args": { ... } },
    { "id": "<uuid>", "type": "read",       "args": { ... } },
    { "id": "<uuid>", "type": "journal",    "args": { ... } }
  ]
}
```

> **The `openrecon` envelope is required on blocks configs too** (not just recon
> YAML). `openrecon validate`/`ingest` reject a blocks config with no top-level
> `openrecon` version key (`missing 'openrecon' version key`). It must match the
> binary's spec version — `openrecon --version` prints it (currently `v0.2.0`).

---

## DataSource args

| Field | Type | Required | Notes |
|---|---|---|---|
| `source_type` | string | yes | `"file"` for Excel/CSV; `"database"` for SQL sources |
| `formats` | list[string] | yes | e.g. `["csv"]`, `["excel"]`, `["csv", "excel"]` |
| `name` | string | no | Human label only |

Valid file formats: `csv`, `tsv`, `excel`, `json`, `jsonl`, `parquet`. Any
other format is rejected up front with a `BlockConfigurationError` naming the
supported set (it does not silently fall through to a CSV read). Format
strings are case-insensitive. `format: "excel"` covers both `.xlsx` and
legacy `.xls` (BIFF) workbooks — `.xls` is read via the `xlrd` engine
automatically.

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "type": "datasource",
  "args": {
    "source_type": "file",
    "formats": ["csv"]
  }
}
```

---

## ReadBlock args

| Field | Type | Required | Notes |
|---|---|---|---|
| `input` | UUID string | yes | DataSource block ID |
| `columns_alias_map` | list[ColumnSpec] | yes | At least one column required |
| `dedup_columns` | list[string] | yes | **REQUIRED, non-empty.** The source-row identity columns — they feed the row's `_dedup_hash`, which (namespaced by the journal block's `pool`) becomes `journal_id`. Choose columns that uniquely and stably identify a business row (txn ref, voucher no + line, …) |
| `enable_dedup` | bool | no (default `false`) | Legacy mode switch, superseded by `dedup_mode` (declaring both is a validation error). `true` ≡ `dedup_mode: "content"`, `false` ≡ `dedup_mode: "positional"` |
| `dedup_mode` | `"content"` \| `"positional"` \| `"file_scoped"` | no | How row identity (`_dedup_hash`) is computed — see "Choosing a dedup mode" below. `"file_scoped"` is required by the openrecon v0.2.0 spec |
| `file_identity_columns` | list[string] | iff `dedup_mode: "file_scoped"` | Columns that uniquely identify the source *file* and are constant within it (e.g. a batch UTR broadcast from the file's summary sheet via `excel_options.cell_extractions`). Required with `"file_scoped"`, forbidden otherwise |
| `csv_options` | dict | conditional | Required if source is CSV |
| `excel_options` | dict | conditional | Required if source is Excel |
| `name` | string | no | Human label |

There is no fallback for `dedup_columns` — omitting it is a validation error
(the old fallback-to-all-columns behaviour was removed because it silently
broke idempotency when sources gained or lost columns). An underspecified
`dedup_columns` key surfaces later as `JournalIdCollisionError` at ingest.

### Choosing a dedup mode

`dedup_mode` decides what happens to (a) identical rows *within* one file
and (b) re-uploads of the *same* file (`"file_scoped"` is required by the
openrecon v0.2.0 spec; the `enable_dedup` boolean covers only the first two
modes):

| Mode | Identical rows within one file | Re-upload of the same file | Use when |
|---|---|---|---|
| `"content"` (≡ `enable_dedup: true`) | Collapsed to one journal | Deduplicated (same content → same `journal_id`) | `dedup_columns` form a natural business key (txn ref, voucher no) |
| `"positional"` (≡ `enable_dedup: false`, default) | Kept as separate journals | **Creates duplicates** — row identity is scoped to the ingest batch | Identical line items are legitimate and re-upload protection is handled outside the config |
| `"file_scoped"` | Kept as separate journals | Deduplicated — identity is `(file fingerprint, row position)`, no batch ingredient | Identical line items are legitimate **and** accidental re-uploads must be safe (e.g. payment-gateway charge annexures where one invoice's ad charge repeats per outlet) |

For `"file_scoped"`, `file_identity_columns` must name columns that are
constant within one file and unique across files, taken from file
**content**, never the filename — typically a batch reference or UTR
broadcast from the file's summary sheet with `excel_options.cell_extractions`,
or an existing constant column. The read fails loudly if a fingerprint
column is missing, null, or varies within the file. Cross-file uniqueness
is your contract: two different files sharing a fingerprint value would
silently supersede each other row-by-row.

```json
{
  "type": "read",
  "args": {
    "dedup_mode": "file_scoped",
    "file_identity_columns": ["bank_utr"],
    "dedup_columns": ["adjustment_type", "invoice_no", "amount"],
    "excel_options": {
      "sheet_name": "Other charges and deductions",
      "cell_extractions": [
        {
          "name": "bank_utr",
          "dtype": "string",
          "sheet": "Summary",
          "locator": {"type": "label_offset", "label": "Bank UTR",
                      "label_column": 1, "value_offset": {"row": 0, "col": 1}}
        }
      ]
    }
  }
}
```

### ColumnSpec shape

```json
{
  "name": "output_column_name",
  "dtype": "string",
  "nullable": true,
  "possible_names": ["Source_Col", "source_col", "SourceCol"]
}
```

| Field | Values | Notes |
|---|---|---|
| `name` | string | Output column name — used in downstream expressions |
| `dtype` | `string`, `integer`, `float`, `boolean`, `date`, `datetime` | Type to cast the column to |
| `nullable` | bool | Whether null values are allowed |
| `possible_names` | list[string] | Alternate header names in the source file (fuzzy header matching) |

### csv_options valid keys

| Key | Type | Default | Notes |
|---|---|---|---|
| `delimiter` | string | `","` | Column separator |
| `header` | bool | `true` | Whether first row is header |
| `skip_rows_before_header` | int or dict | — | Rows to skip before header row |
| `skip_rows_after_header` | int or dict | — | Rows to skip after header row |
| `end_row` | int or dict | — | Stop reading at this row |
| `quote_char` | string | `"\""` | Quote character |
| `escape_char` | string | `"\\"` | Escape character |
| `null_values` | list[string] | — | Strings to treat as null |
| `true_values` | list[string] | — | Strings to treat as boolean true |
| `false_values` | list[string] | — | Strings to treat as boolean false |

Note: `has_header` is NOT a valid key. Use `header` (boolean).

For dict-form skip options: `{"condition": "<string_to_match>", "occurence": <int>}`.

### excel_options valid keys

| Key | Type | Default |
|---|---|---|
| `sheet_name` | int or string | `0` (first sheet) |
| `header` | bool | `true` |
| `skip_rows_before_header` | int or dict | — |
| `skip_rows_after_header` | int or dict | — |
| `end_row` | int or dict | — |
| `skip_blank_rows` | bool | `true` |
| `null_values` | list[string] | — |
| `true_values` | list[string] | — |
| `false_values` | list[string] | — |

---

## SelectBlock args

Computes derived columns via expressions, and optionally drops rows where a
boolean expression evaluates false. One SelectBlock handles both projection
and filtering — you usually don't need two.

| Field | Type | Required | Notes |
|---|---|---|---|
| `input` | UUID string | yes | Upstream block ID |
| `columns` | list[ColumnConfig] | yes | At least one; replaces all upstream columns |
| `filters` | Expression dict | no | Boolean expression; rows where it evaluates `false` are dropped before emit |
| `name` | string | no | Human label |

`columns` is a list of `{"name": "<output_col>", "expression": <expr>}` entries.
The `expression` is any expression from `grammars/EXPRESSIONS.md` (col_ref,
literal, concat, coalesce, case, cast, arithmetic, etc.).

### filters example — filter rows, then project

```json
{
  "type": "select",
  "args": {
    "input": "<read-block-uuid>",
    "filters": {
      "type": "equals",
      "args": [
        {"type": "col_ref", "name": "status", "table": "parent"},
        {"type": "literal", "value": "active", "dtype": "string"}
      ]
    },
    "columns": [
      {"name": "id",     "expression": {"type": "col_ref", "name": "id",     "table": "parent"}},
      {"name": "amount", "expression": {"type": "col_ref", "name": "amount", "table": "parent"}}
    ]
  }
}
```

`filters` is the idiomatic way to translate legacy "selection filter"
patterns. Authoring a separate filter-only SelectBlock upstream is not
needed — put the filter expression on the same SelectBlock that declares
your derived columns.

---

## JournalBlock args

| Field | Type | Required | Validation |
|---|---|---|---|
| `input` | UUID string | yes | Must reference an upstream block |
| `source` | string | yes | Non-empty literal tag (e.g. `"bank"`, `"erp"`) |
| `pool` | string | yes | **REQUIRED.** Lowercase slug matching `^[a-z0-9_-]{1,64}$` (e.g. `"bank_pool"`, `"erp"`). The identity namespace for this block's journals — see "The pool label" below |
| `date_expr` | Expression dict | yes | Parent scope only; evaluates to a date |
| `debit_entries` | list[EntryConfig] | yes | At least 1 required |
| `credit_entries` | list[EntryConfig] | yes | At least 1 required |
| `identifiers` | dict[string, col_ref] | yes | **REQUIRED, non-empty** (matching is impossible without identifiers). ColumnRef-only; parent scope only |
| `primary_identifier` | string | no | When set, must name a key declared in `identifiers` |
| `raw` | dict[string, col_ref] | no | ColumnRef-only; parent scope only |
| `name` | string | no | Human label |

**There is no `id_expr`.** The journal's `journal_id` is system-derived: the
upstream row's `_dedup_hash` (from the read block's `dedup_columns`)
namespaced under this block's `pool` label. User-authored journal IDs are
not supported — an `id_expr` key is rejected as an unknown field
(`extra_forbidden`). Control identity via `dedup_columns` + `pool`.

### The pool label (required by the openrecon v0.2.0 spec)

Every journal block must declare a `pool` — an author-supplied label that
namespaces journal identity:

- `journal_id` is derived from the row's dedup hash **and** the pool label
  (`sha256(jcs({"hash": _dedup_hash, "pool": pool}))`). Two unrelated rows
  with the same dedup key in *different* pools get distinct `journal_id`s;
  the same content in the *same* pool dedups by contract.
- `pool` is stamped as a first-class column on stored journals, next to
  `source`, and is what recon match sides scope by (every match side's
  `pick` must anchor on `field: pool` — see `RECON.md`).
- Multiple journal blocks (same or different `source`) MAY share a pool
  label to contribute to one logical pool. The label — not the block id —
  is the durable namespace.

Choosing pools: give each business stream of journals its own pool
(`bank`, `erp_ap`, `settlement_pool`, …). The simplest valid scheme is
`pool` = `source`; use a shared pool when several sources feed one logical
side of a recon.

### Within-batch identity collision (ingest-time guard)

If two rows in one ingest batch produce the same `journal_id`:

- **identical content** → collapsed to one journal (legitimate dedup);
- **differing content** → the whole ingest fails with
  `JournalIdCollisionError`, naming the pool, the contributing journal
  blocks, and the columns that disagree — the fix is a better-specified
  dedup key (read block `dedup_columns`) or distinct pools.

`openrecon validate` additionally emits a `duplicate_journal_definition`
warning when multiple journal blocks in one pool sit on structurally
identical upstream chains (a copy-paste config smell).

### Re-ingest semantics (library storage backends)

In the library's journal-storage read path (`JournalStorage.scan()`),
re-ingesting the same content under a new batch supersedes the prior copy at
read time — newest batch wins per `(source, journal_id)`. This is what makes
`dedup_mode: "file_scoped"` re-upload-safe: a re-upload reproduces the same
`journal_id`s, so the new batch's copies win and nothing duplicates (under
`"positional"` the batch id is folded into the hash, so every upload mints
fresh `journal_id`s instead). For the **local
CLI**, the safe pattern is unchanged: point `--out` at a fresh directory when
iterating on a config (appending re-runs of the same data to one `--out` dir
can still duplicate journals in the regenerated JSON sidecars).

### EntryConfig shape

| Field | Type | Required | Notes |
|---|---|---|---|
| `account` | string | yes | Non-empty GL account name (literal string) |
| `direction` | `"DR"` or `"CR"` | yes | Set by which list the entry appears in (debit_entries → DR, credit_entries → CR) |
| `value` | Expression dict | yes | Parent scope only; evaluates to a numeric amount |
| `currency` | Expression dict | yes | **REQUIRED.** Parent scope only; resolves to an ISO 4217 string. Usually a literal: `{"type": "literal", "value": "INR", "dtype": "string"}`. Journals must balance per currency |
| `category` | string | no | Semantic tag: `"TDS"`, `"commission"`, etc. |
| `ledger_entry_fields` | dict[string, Expression] | no | Extra per-leg metadata; parent scope only |

Note: `direction` is inferred from the list — you do not set it explicitly in the dict. The block validates that entries in `debit_entries` always become `DR` and `credit_entries` always become `CR`.

### Scoping rule

All expressions in JournalBlock — `date_expr`, entry `value` / `currency` expressions, `identifiers` values, `raw` values — must use scope `"parent"`. Any other scope raises `BlockValidationError`.

### identifiers and raw constraints

Both `identifiers` and `raw` accept only `col_ref` expressions (not computed expressions). If you need to derive a value first, do it in an upstream `SelectBlock` and then reference the derived column here.

---

## Validation layers

### Author-time (block `from_dict`)

Errors raise `BlockValidationError` before any data is read.

| Check | Error message |
|---|---|
| Block ID not a valid UUID | `"Invalid block ID"` |
| `source` empty or not a string | `"source must be a non-empty string"` |
| `pool` missing or empty | pool is required (pydantic schema + plan compiler both reject) |
| `pool` not a lowercase slug | `"pool must match ^[a-z0-9_-]{1,64}$ — a lowercase slug ..."` |
| `col_ref` with non-`parent` table in any expression | `"Journal expressions must use 'parent' scope"` |
| `identifiers` or `raw` value is not a `col_ref` | `"Must be a column reference"` |
| `debit_entries` list is empty | `"At least one debit entry required"` |
| `credit_entries` list is empty | `"At least one credit entry required"` |
| Entry missing `account` field | `"account is required and must be a non-empty string"` |
| Entry missing `value` field | `"value is required"` |
| Entry missing `currency` field | pydantic `Field required` on `.../currency` |
| Read block missing `dedup_columns` | pydantic `Field required` on `/blocks/N/args/dedup_columns` |
| `identifiers` missing or empty | pydantic error — at least one identifier required |
| `id_expr` present | `Extra inputs are not permitted` (`extra_forbidden`) — journal IDs are system-derived |

### Row-time (JournalBlockExecutor)

Failing rows go to `failure_df` with a `_error_message` column.

| Check | Error message pattern |
|---|---|
| `date_expr` evaluates to null | `"null journal date (date_expr)"` |
| Any entry `value` evaluates to null | `"null value in debit_entries[N] (account=X)"` |
| Any entry `currency` evaluates to null | `"null currency in debit_entries[N] (account=X)"` |
| `sum(DR) != sum(CR)` within a currency (exact Decimal comparison) | `"Unbalanced journal for currency C: ..."` |
| All identifiers null (when identifiers dict is non-empty) | `"No identifier present"` |

### Ingest-time (whole batch)

| Check | Behaviour |
|---|---|
| Two rows in one batch, same `journal_id`, identical content | Collapsed to one journal (silent, legitimate dedup) |
| Two rows in one batch, same `journal_id`, differing content | Whole ingest fails with `JournalIdCollisionError` naming the pool, journal blocks, and disagreeing columns |

---

## Pattern examples

### Pattern 1: one-row-per-journal (bank statement)

Source: one row per transaction, separate Debit/Credit columns.

```json
{
  "blocks": [
    {
      "id": "11111111-0000-0000-0000-000000000001",
      "type": "datasource",
      "args": {"source_type": "file", "formats": ["csv"]}
    },
    {
      "id": "11111111-0000-0000-0000-000000000002",
      "type": "read",
      "args": {
        "input": "11111111-0000-0000-0000-000000000001",
        "columns_alias_map": [
          {"name": "bank_ref", "dtype": "string", "nullable": false, "possible_names": ["Bank_Ref", "TxnRef"]},
          {"name": "value_date", "dtype": "date", "nullable": false, "possible_names": ["Value_Date", "Date"]},
          {"name": "utr", "dtype": "string", "nullable": true, "possible_names": ["UTR", "UTR_Number"]},
          {"name": "narration", "dtype": "string", "nullable": true, "possible_names": ["Narration", "Description"]},
          {"name": "debit_amt", "dtype": "float", "nullable": true, "possible_names": ["Debit", "Dr"]},
          {"name": "credit_amt", "dtype": "float", "nullable": true, "possible_names": ["Credit", "Cr"]}
        ],
        "dedup_columns": ["bank_ref"],
        "csv_options": {"delimiter": ",", "header": true}
      }
    },
    {
      "id": "11111111-0000-0000-0000-000000000003",
      "type": "journal",
      "args": {
        "input": "11111111-0000-0000-0000-000000000002",
        "source": "bank",
        "pool": "bank",
        "date_expr": {"type": "col_ref", "name": "value_date", "table": "parent"},
        "debit_entries": [
          {
            "account": "Bank",
            "value": {"type": "col_ref", "name": "debit_amt", "table": "parent"},
            "currency": {"type": "literal", "value": "INR", "dtype": "string"}
          }
        ],
        "credit_entries": [
          {
            "account": "Bank",
            "value": {"type": "col_ref", "name": "credit_amt", "table": "parent"},
            "currency": {"type": "literal", "value": "INR", "dtype": "string"}
          }
        ],
        "identifiers": {
          "utr": {"type": "col_ref", "name": "utr", "table": "parent"}
        },
        "raw": {
          "narration": {"type": "col_ref", "name": "narration", "table": "parent"}
        }
      }
    }
  ]
}
```

Note: This pattern only works when every row has EITHER a debit OR a credit (not both). If rows can have both, add a second entry on each side or derive a net amount upstream.

### Pattern 2: grouped-rows (ERP voucher with multiple legs)

Source: multiple rows per voucher, each row is one GL leg.

Add a `GroupByBlock` between Read and Journal:

```json
{
  "id": "22222222-0000-0000-0000-000000000003",
  "type": "groupby",
  "args": {
    "input": "22222222-0000-0000-0000-000000000002",
    "by": [
      {"type": "col_ref", "name": "voucher_no", "table": "parent"}
    ],
    "aggregations": [
      {
        "name": "posting_date",
        "expression": {"type": "first", "args": [{"type": "col_ref", "name": "posting_date", "table": "parent"}]},
        "dtype": "date"
      },
      {
        "name": "utr",
        "expression": {"type": "first", "args": [{"type": "col_ref", "name": "utr", "table": "parent"}]},
        "dtype": "string"
      },
      {
        "name": "ap_amount",
        "expression": {
          "type": "sum",
          "args": [{"type": "col_ref", "name": "amount", "table": "parent"}]
        },
        "dtype": "float"
      }
    ]
  }
}
```

The JournalBlock then reads `voucher_no`, `posting_date`, `utr`, `ap_amount` from the grouped row.

### Pattern 3: derived identifier (parse UTR from narration)

When UTR is embedded in a narration string, derive it in a `SelectBlock`:

```json
{
  "id": "33333333-0000-0000-0000-000000000003",
  "type": "select",
  "args": {
    "input": "33333333-0000-0000-0000-000000000002",
    "columns": [
      {
        "name": "bank_ref",
        "expression": {"type": "col_ref", "name": "bank_ref", "table": "parent"}
      },
      {
        "name": "utr_extracted",
        "expression": {
          "type": "regex_extract",
          "args": [
            {"type": "col_ref", "name": "narration", "table": "parent"},
            {"type": "literal", "value": "UTR[:\\s]+([A-Z0-9]+)", "dtype": "string"},
            {"type": "literal", "value": 1, "dtype": "integer"}
          ]
        },
        "dtype": "string"
      }
    ]
  }
}
```

Then in JournalBlock `identifiers`:

```json
"identifiers": {
  "utr": {"type": "col_ref", "name": "utr_extracted", "table": "parent"}
}
```

---

## Common gotchas

- UUIDs are required on every block. Generate them; do not use short strings.
- `pool` is required on every journal block and must be a lowercase slug (`^[a-z0-9_-]{1,64}$`). Recon match sides scope by pool, so pick pool labels with the downstream recon config in mind (simplest scheme: `pool` = `source`).
- There is no `id_expr` — `journal_id` is system-derived from the read block's `dedup_columns` hash, namespaced by `pool`. Pick `dedup_columns` that are unique and stable per business row.
- Every entry needs a `currency` expression (usually a string literal like `"INR"`), and journals must balance per currency.
- dtype names in `columns_alias_map` are: `string`, `integer`, `float`, `boolean`, `date`, `datetime`. Not `str`, `int`, `double`, `datetime64`, etc.
- `identifiers` and `raw` are ColumnRef-only. If you need `concat(col_a, col_b)` as an identifier, put the concat in SelectBlock and reference the result column here.
- The `direction` field is not in the entry dict — it is implicit from whether the entry is in `debit_entries` or `credit_entries`.
- `csv_options.header` is a boolean. The key `has_header` does not exist and will raise `BlockValidationError`.
