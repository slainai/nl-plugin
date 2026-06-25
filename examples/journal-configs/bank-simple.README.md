# bank-simple.json

## What raw file it runs against

`recon_lab/data/raw_excel/bank.xlsx` — sheet `Transactions`

Real columns confirmed: `Bank_Ref`, `Value_Date`, `UTR_Number`, `Narration`, `Debit`, `Credit`

## Blocks used and why

| Block | Purpose |
|---|---|
| `DataSource` | Declares an Excel file source |
| `ReadBlock` | Maps raw headers to normalized aliases via `possible_names` fuzzy matching; reads `Debit`/`Credit` as `string` (`debit_raw`/`credit_raw`) so the cast is explicit |
| `SelectBlock` | Casts `debit_raw`/`credit_raw` → `float` as `debit_amt`/`credit_amt`; derives `direction` (debit/credit) via a `case` expression; derives `txn_amount` via `greatest` |
| `JournalBlock` | Emits one journal per row using the cast float `txn_amount` for both DR and CR entries; stamps `pool: "bank"` as the identity namespace |

The `SelectBlock` is required here because `Debit`/`Credit` arrive as `Int64` from the Excel reader. Casting them to `float` in the `ReadBlock` dtype field alone is insufficient — the executor reads them as integers and the `greatest` + arithmetic path in `JournalBlockExecutor` needs a proper float column. The `SelectBlock` casts them explicitly before they reach the journal.

## How to execute

```bash
WORKDIR=$(mktemp -d)
echo '{"identifiers": ["utr"]}' > "$WORKDIR/identifiers.json"
openrecon ingest examples/journal-configs/bank-simple.json \
  --identifiers "$WORKDIR/identifiers.json" \
  --input bank_source=recon_lab/data/raw_excel/bank.xlsx \
  --out "$WORKDIR"
```

Writes `journals.json` and `entries.json` to `$WORKDIR`. The `bank_source`
name must match the datasource block's `args.name` in the config. The
`--identifiers` spec must declare every identifier key the journal block
uses (here just `utr`).

## Expected output shape

- `journals_df`: one row per bank statement row; columns include `id`, `source` (`"bank"`), `date`, `identifiers` (with `utr`), `raw` (with `narration` and `direction`)
- `entries_df`: two rows per journal — one DR `BankAccount` and one CR `Counterparty`, both carrying `txn_amount` as a float
- Rows with both debit and credit zero would produce zero-value entries; the sample data has no such rows

## Grammar patterns demonstrated

- DataSource → ReadBlock → SelectBlock → JournalBlock chain
- `excel_options.sheet_name` for named sheet targeting
- `possible_names` for header-name aliasing
- Explicit int→float cast via `cast` expression in a SelectBlock
- `case` expression using the `[{condition, result}]` when-clause list format with an else fallback
- `greatest` to pick the non-zero value from two exclusive columns
- Separate `debit_entries` / `credit_entries` both drawing from a single unified `txn_amount` column
- `identifiers` and `raw` as ColumnRef-only dicts
