# erp-with-select.json

## What raw file it runs against

`recon_lab/data/raw_excel/erp_ap.xlsx` — sheet `AP_Ledger`

Real columns confirmed: `Voucher_No`, `Posting_Date`, `Vendor_Code`, `UTR`, `Invoice_No`, `Payment_Mode`, `Account`, `Dr_Cr`, `Amount`

## Blocks used and why

| Block | Purpose |
|---|---|
| `DataSource` | Declares an Excel file source |
| `ReadBlock` | Maps all nine raw AP_Ledger columns to normalized names; reads `UTR` as `utr_raw` |
| `SelectBlock` | Derives `canonical_utr` by coalescing `utr_raw` with a fallback (`"ERP-" + voucher_no`) |
| `JournalBlock` | References `canonical_utr` in `identifiers` — possible because SelectBlock made it a real column |

The `SelectBlock` is required here because `identifiers` in JournalBlock accepts only `col_ref` expressions (not computed expressions). The coalesce logic must live in SelectBlock; JournalBlock just references the output column by name.

## How to execute

```bash
WORKDIR=$(mktemp -d)
echo '{"identifiers": ["utr", "vendor_code"]}' > "$WORKDIR/identifiers.json"
openrecon ingest examples/journal-configs/erp-with-select.json \
  --identifiers "$WORKDIR/identifiers.json" \
  --input erp_source=recon_lab/data/raw_excel/erp_ap.xlsx \
  --out "$WORKDIR"
```

Writes `journals.json` and `entries.json` to `$WORKDIR`. The `erp_source`
name must match the datasource block's `args.name` in the config. The
`--identifiers` spec must declare every identifier key the journal block
uses (`utr`, `vendor_code`).

## Expected output shape

- `journals_df`: one row per AP_Ledger row (not per voucher — no GroupBy); `source` = `"erp"`, `pool` = `"erp"`
- `entries_df`: two rows per journal (`Expenses` DR, `AccountsPayable` CR)
- `identifiers` contains `utr` (from `canonical_utr`) and `vendor_code`
- `raw` contains `invoice_no` and `payment_mode`

Note: Because there is no GroupByBlock, each GL line row in the source produces its own journal. For one-journal-per-voucher behaviour, see `multi-leg-voucher.json`.

## Grammar patterns demonstrated

- `SelectBlock` with `coalesce` to build a fallback-safe identifier column
- `concat` with a `literal` prefix to synthesize a value when the source column is null
- Passing a SelectBlock-derived column through to `JournalBlock.identifiers` as a `col_ref`
- `possible_names` aliasing for columns whose header varies across ERP exports
