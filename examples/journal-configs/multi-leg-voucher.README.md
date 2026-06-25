# multi-leg-voucher.json

## What raw file it runs against

`recon_lab/data/raw_excel/erp_ap.xlsx` — sheet `AP_Ledger`

Real columns confirmed: `Voucher_No`, `Posting_Date`, `Vendor_Code`, `UTR`, `Account`, `Dr_Cr`, `Amount`

The AP_Ledger sheet has multiple rows per voucher (one per GL leg). For example, `ERP-001` appears three times: once for `AP` (CR 50000), once for `Input_GST` (DR 9000), once for `Expenses` (DR 41000).

## Blocks used and why

| Block | Purpose |
|---|---|
| `DataSource` | Declares an Excel file source |
| `ReadBlock` | Maps all AP_Ledger columns; `Invoice_No` and `Payment_Mode` omitted here to keep example focused |
| `GroupByBlock` | Collapses multiple rows per `voucher_no` into one row using aggregates |
| `JournalBlock` | Receives one row per voucher and emits one balanced journal |

The `GroupByBlock` is the key block here. It uses:
- `first` to pick the date, vendor_code, and UTR from the first row of each group
- `sum` to aggregate all amounts (note: the aggregated total will be the net of all legs)
- `count` to carry forward how many GL lines were collapsed
- `collect_set` to capture the distinct accounts touched by this voucher

## How to execute

```bash
WORKDIR=$(mktemp -d)
echo '{"identifiers": ["utr", "vendor_code"]}' > "$WORKDIR/identifiers.json"
openrecon ingest examples/journal-configs/multi-leg-voucher.json \
  --identifiers "$WORKDIR/identifiers.json" \
  --input erp_multileg_source=recon_lab/data/raw_excel/erp_ap.xlsx \
  --out "$WORKDIR"
```

Writes `journals.json` and `entries.json` to `$WORKDIR`. The
`erp_multileg_source` name must match the datasource block's `args.name` in
the config.

## Expected output shape

- `journals_df`: one row per distinct `Voucher_No` (fewer rows than the raw file)
- `entries_df`: two rows per journal (`Expenses` DR, `AccountsPayable` CR) using the summed `total_dr_amount`
- `identifiers` contains `utr` and `vendor_code`
- `raw` contains `accounts_list` (the collected set of GL accounts for that voucher)

## Balancing caveat

The `sum` aggregation adds all leg amounts regardless of direction — AP_Ledger mixes DR and CR rows. If your source needs separate DR and CR sums, add a `SelectBlock` before GroupBy to filter by `Dr_Cr` column, or use a `CASE` expression inside the aggregation. This example keeps it simple: `total_dr_amount` holds the sum of all amounts and is used symmetrically for both the DR and CR entry so the journal is balanced.

## Grammar patterns demonstrated

- `GroupByBlock` upstream of `JournalBlock` (the grouped-rows pattern)
- `first` aggregate to carry forward header-level fields (date, UTR)
- `sum` aggregate for amount rollup
- `count` aggregate (zero-arg form)
- `collect_set` aggregate to gather a list of distinct values per group
- GroupBy output columns used directly as `col_ref` in JournalBlock
