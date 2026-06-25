# erp-bank-utr.yaml

## What journal pool it expects

Journals produced by running `bank-simple.json` and `erp-with-select.json` (or equivalent pipelines) and merging their outputs into one pool.

Required per journal:

| Source | `pool` value (side anchor) | Required identifier key |
|---|---|---|
| ERP AP journal | `"erp"` | `identifiers.utr` |
| Bank statement journal | `"bank"` | `identifiers.utr` |

Each side's `pick` anchors on the journal's `pool` label (required since
numberlabs 0.19) — the example journal configs stamp `pool` = `source`.

Required per entry:

| Source | Account name | Direction |
|---|---|---|
| ERP | `"AccountsPayable"` | CR |
| Bank | `"BankAccount"` | DR |

## How to execute

```bash
openrecon run examples/recon-configs/erp-bank-utr.yaml \
  --journals "$WORKDIR" \
  --out      "$WORKDIR/results"
```

`--journals` is the output **directory** of a prior `openrecon ingest` run —
here, one directory into which both `bank-simple.json` and
`erp-with-select.json` were ingested (run both ingests with the same
`--out`). Exit code 0 = all matched, 1 = some unclaimed (inspect
`result.json`), 2 = invalid config.

## Expected output

- Journals with matching `identifiers.utr` values and amounts within 100 INR → `Match(match_type='auto')`
- A UTR shared by several ERP journals where only one passes the amount criterion → still an auto-match (exactly one candidate survives both criteria)
- Journals with no UTR + amount match on the other side → unclaimed (appear in unmatched pool)

With the sample data (`bank.xlsx` via `bank-simple.json`, 4 bank journals; `erp_ap.xlsx` via `erp-with-select.json`, 14 per-GL-line ERP journals): **3 auto-matches** (UTR-AA001/2/3, including AA003's 50-INR tolerance match), `UTR-NOREF` and the orphan/extra ERP lines unclaimed — exit code 1.

## Grammar patterns demonstrated

- Two-pool rule with `identity` unit strategy (one-to-one matching)
- Mandatory pool anchor on each side's `pick`
- Symmetric criterion: `identifiers.utr` equals across both sides
- Asymmetric criterion: different `entries[account=...]` path per side (`AccountsPayable` on ERP, `BankAccount` on bank)
- `within` comparator with a Decimal tolerance string for amount fuzzy matching
- Hello-world config: the simplest possible two-pool recon
