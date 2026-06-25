# three-way-match.yaml

## What journal pool it expects

Journals from three sources, each stamped with the appropriate `pool` label and carrying a `po_number` identifier.

| Source | `pool` value (side anchor) | Required identifier key | Key account |
|---|---|---|---|
| Purchase Order | `"po"` | `identifiers.po_number` | `"AP"` |
| Goods Receipt Note | `"grn"` | `identifiers.po_number` | `"Inventory"` |
| Vendor Invoice | `"invoice"` | `identifiers.po_number` | `"AP"` |

Each side's `pick` anchors on the journal's `pool` label (required since
numberlabs 0.19); the ingest configs producing these journals must declare
`pool: "po"` / `"grn"` / `"invoice"` on their journal blocks.

Each journal must have an `AP` or `Inventory` entry so the amount criteria resolve correctly.

See `recon_lab/data/po_grn_invoice.json` for a sample pool that matches this shape.

## How to execute

```bash
openrecon run examples/recon-configs/three-way-match.yaml \
  --journals "$INGEST_OUT_DIR" \
  --out "$WORKDIR"
```

`--journals` is the output directory of a prior `openrecon ingest` run (it
reads `journals.json` + `entries.json`, or `journals.parquet`). Exit code
0 = all matched, 1 = some unclaimed (inspect `$WORKDIR/result.json`),
2 = invalid config.

## Expected output

- Triples (PO + GRN + Invoice) sharing the same `po_number` and within tolerances → `Match(match_type='auto')`
- Matches where the three-way AP amount differs by more than 1500 INR → match recorded + `ResolutionItem(type='validation_failure', flag='three_way_amount_mismatch')`
- Journals with no matching triple → unclaimed

## Grammar patterns demonstrated

- Three-sided rule (more than two `sides`)
- Two separate `between` pairs within one rule's `criteria` list to link all three sides via the same identifier key
- `all_sides_equal` validation post-condition across three sides
- `identity` unit strategy for strict one-from-each-source matching
- Asymmetric amount criteria referencing different account names per source
- Tolerance strings as quoted Decimal values (`"1000"`, `"500"`, `"1500"`)
