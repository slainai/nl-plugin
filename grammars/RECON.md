# Recon YAML Grammar

Grammar reference for authoring `ReconUnit` configs consumed by the recon engine.

**Starting point:** the journals your Task A pipeline emitted — not external adapters.
The identifier keys and raw keys you reference here (`identifiers.utr`, `raw.narration`)
come from the `identifiers` and `raw` dicts you declared in your JournalBlock config.

---

## Using Task A output

Task A is run via `openrecon ingest`, which writes canonical journal files
to its `--out` directory (`journals.json` + `entries.json`, plus
`journals.parquet`). That directory feeds directly into `openrecon run`:

```bash
openrecon ingest pipeline.json \
  --identifiers identifiers.json \
  --input bank_source=./data/bank.xlsx \
  --out "$WORKDIR"

openrecon run match.yaml \
  --journals "$WORKDIR" \
  --out      "$WORKDIR/results"
```

The match engine writes `result.json` to `--out`. Exit 0 = all matched, exit
1 = some unclaimed (inspect `result.json`), exit 2 = invalid config.

The identifier keys (`identifiers.utr`, etc.) and raw keys (`raw.narration`)
that you reference in this file must match the dicts you declared in the Task
A `JournalBlock` config — they travel verbatim through `journals.json` into
the match engine. Likewise the **pool labels** your sides scope by must match
the `pool` declared on the Task A journal blocks.

---

## YAML config schema

A config file wraps one `ReconUnit` in the OpenRecon envelope. The CLI
(`openrecon validate`, `openrecon run`) requires the envelope for
auto-detection, and rejects an envelope version that does not match the
openrecon binary's spec version (`openrecon --version` prints it) with a
`version_mismatch` error.

```yaml
openrecon: v0.2.0                     # envelope version — must match the binary's spec (openrecon --version)
match:                                # one ReconUnit keyed under `match`
  name: string                        # required

  operations:                         # ordered list; earlier ops claim journals first
    - name: string                    # Rule — `type:` omitted defaults to rule
      behavior: auto_match            # auto_match | always_suggest | skip
      sides:
        - name: string
          pick:                       # MUST contain a pool anchor (see §1)
            - field: pool             # required anchor: op equals|in on field pool
              op: equals
              value: string           # a pool label from the Task A journal blocks
            - field: string           # optional refinements (source, identifiers.X, ...)
              op: equals              # equals | in | exists | matches
              value: any
          unit:
            kind: identity            # identity | bucket | subset_search | connected_components
            by: string                # bucket: grouping path
            max_size: 5               # subset_search only
            by: [string, ...]         # connected_components only
      criteria:
        - field: string               # symmetric path, OR:
          field:
            side_name_a: string
            side_name_b: string
          comparator: equals          # equals | within | explained_by_sibling
          config:
            tolerance: "100"          # within (Decimal string)
            days: 3                   # within on dates
            category: TDS             # explained_by_sibling
          between: [side_a, side_b]
      validation:
        type: ratio_lte               # ratio_lte | all_sides_equal | amount_within
        config:
          numerator: raw.commission
          denominator: raw.gross
          threshold: "0.15"
          field: entries.amount
          tolerance: "0"
          between: [a, b]
        flag: string

    - name: string                    # nested ReconUnit
      type: recon_unit                # REQUIRED to mark a nested unit
      operations: [...]
      cross_source_checks: [...]

  cross_source_checks:
    - name: string
      account: string                 # GL account name (exact)
      actual: string                  # source producing GL view
      expected: string                # external source
      tolerance: "0"                  # Decimal string
      flag: balance_mismatch
```

### Discrimination — Rule vs nested ReconUnit

Operations are `Union[Rule, ReconUnit]` discriminated by an explicit `type:`
field. Valid values are `rule` and `recon_unit`; any other value is a
validation error (`Unknown operation type: ...`).

- `type:` **omitted** → defaults to a **Rule** (so a plain matching rule needs
  no `type:`; give it `sides:` + `criteria:`).
- `type: recon_unit` → a **nested ReconUnit**, and it is **required** to nest.
  A bare `operations:` block with no `type:` is parsed as a Rule and fails
  validation on its (empty) `sides:`.
- `type: rule` is accepted but redundant.

The Python API (`loads_recon_config`, `run_match`) also accepts a bare
ReconUnit (no envelope). The CLI only accepts the envelope.

---

## Field Path DSL

Resolves a value from a journal (or a multi-member unit).

| Path | Resolves to | Type |
|---|---|---|
| `"pool"` | `journal.pool` — the identity namespace stamped by the journal block | `str \| None` |
| `"source"` | `journal.source` | `str` |
| `"date"` | `journal.date` | `date` |
| `"identifiers.X"` | `journal.identifiers["X"]` | `str \| None` |
| `"raw.X"` | `journal.raw["X"]` | `str \| None` |
| `"entries.amount"` | Sum of all entry amounts | `Decimal` |
| `"entries[account=\"X\"].amount"` | Sum of entries where account==X | `Decimal \| None` |
| `"entries[direction=\"CR\"].amount"` | Sum of CR entries | `Decimal \| None` |
| `"entries[category=\"TDS\"].amount"` | Sum of entries with category==TDS | `Decimal \| None` |
| `"entries[account=\"X\",direction=\"DR\"].amount"` | Sum where ALL predicates hold | `Decimal \| None` |

`X` in `identifiers.X` and `raw.X` must match a key you declared in JournalBlock.

**None propagation:** If a path resolves to `None` on either side of a criterion, the criterion does not hold. Two journals both lacking a field do not false-match on that field.

**Multi-member units (Bucket, ConnectedComponents):** amount paths are summed; all other paths must agree across members (disagreement → `None`).

---

## 1. Filter

Picks journals from the pool.

| op | Semantics |
|---|---|
| `equals` | `resolve(field) == value` |
| `in` | `resolve(field) in value` (value is a list) |
| `exists` | `resolve(field) is not None` |
| `matches` | `re.search(value, resolve(field))` |

Multiple filters on a Side are AND-combined.

### Mandatory pool anchor (required by the openrecon v0.2.0 spec)

**Every side's `pick` MUST contain a pool anchor**: a filter on `field: pool`
with `op: equals` (string value) or `op: in` (non-empty list of strings).
A side scoped only by `source` (or anything else) is rejected at validation:

> `side 'X' must scope by pool: its `pick` requires a filter on field 'pool'
> with op 'equals' or 'in' (#40) ...`

The pool is the unit of matching intent — a pool may span multiple sources,
and a pool-scoped rule stays stable as a pool gains or loses a source.
`source` and other fields survive as optional *refinements* on top of the
pool anchor, never as the anchor itself.

Pre-pool legacy journals read back `pool = NULL` and are never picked by a
pool-scoped side (the standard `None`-handling rule: a filter resolving to
`None` excludes the journal). They stay inert until re-ingested with a pool.

```yaml
pick:
  - field: pool                  # required anchor
    op: equals
    value: erp
  - field: source                # optional refinement
    op: equals
    value: erp_ap_export
  - field: identifiers.utr
    op: exists
```

---

## 2. UnitStrategy

Controls how picked journals on a Side are grouped.

| kind | Behavior |
|---|---|
| `identity` | Each journal is its own 1-member unit (default) |
| `bucket` | Journals sharing the same `by` value form one unit; `None` on `by` → dropped |
| `subset_search` | Finds subsets whose summed amount equals the other side; `max_size` controls search depth |
| `connected_components` | DSU: links journals sharing any value in the `by` list (must be scalar string paths) |

```yaml
unit:
  kind: bucket
  by: identifiers.batch_ref
```

```yaml
unit:
  kind: subset_search
  max_size: 5
```

```yaml
unit:
  kind: connected_components
  by:
    - identifiers.order_id
    - identifiers.settlement_id
```

---

## 3. MatchCriterion

Compares path values across two sides.

| comparator | Config | Semantics |
|---|---|---|
| `equals` | — | `val_a == val_b` |
| `within` | `tolerance: "<Decimal>"` or `days: <int>` | `abs(val_a - val_b) <= threshold` |
| `explained_by_sibling` | `category: "<string>"` | `abs(val_a - val_b) == sum of side-A entries with that category` |

Symmetric (same path on both sides):
```yaml
criteria:
  - field: identifiers.utr
    comparator: equals
    between: [erp, bank]
```

Asymmetric (different path per side):
```yaml
criteria:
  - field:
      erp: "entries[account=\"AP\"].amount"
      bank: entries.amount
    comparator: within
    config:
      tolerance: "100"
    between: [erp, bank]
```

---

## 4. Rule behavior

| behavior | 0 candidates | 1 candidate | N candidates |
|---|---|---|---|
| `auto_match` | nothing | `Match(match_type='auto')` | `ResolutionItem(needs_selection)` |
| `always_suggest` | nothing | `ResolutionItem(needs_confirmation)` | `ResolutionItem(needs_selection)` |
| `skip` | nothing | journals consumed, no output | journals consumed, no output |

**`skip` invariants:** exactly 1 side, no criteria.

---

## 5. ValidationRule

Post-condition checked after a match forms (or per picked journal for 1-side Rules).
Failure produces a `ResolutionItem(type='validation_failure')`. The match is still recorded.

| type | Config keys | Semantics |
|---|---|---|
| `ratio_lte` | `numerator`, `denominator`, `threshold` | `numerator/denominator > threshold` → fail |
| `all_sides_equal` | `field`, `tolerance` | max across all sides - min > tolerance → fail |
| `amount_within` | `between`, `field`, `tolerance` | abs diff between two specified sides > tolerance → fail |

```yaml
validation:
  type: ratio_lte
  config:
    numerator: raw.commission
    denominator: raw.gross
    threshold: "0.15"
  flag: commission_overcharge
```

---

## 6. CrossSourceCheck

Verifies a GL account balance matches an external source total. Runs after all operations.

```yaml
cross_source_checks:
  - name: input_gst_vs_gstr2a
    account: Input_GST
    actual: erp
    expected: gstr_2a
    tolerance: "0"
    flag: gst_mismatch
```

---

## 7. ReconUnit composition

A config wraps exactly **one** top-level `ReconUnit` under `match:`, whose
ordered `operations:` list can hold Rules **and** nested `ReconUnit`s
(`type: recon_unit`). Nesting serves two distinct purposes — both first-class:

### 7a. Priority staging (exact pass → fuzzy pass)

Operations execute in order — earlier operations claim journals first, so put
high-confidence rules ahead of fuzzy ones.

```yaml
openrecon: v0.2.0
match:
  name: full_recon
  operations:
    - name: exact_pass
      type: recon_unit                # nested ReconUnit — required to nest
      operations:
        - name: exact_utr             # Rule — `type:` omitted defaults to rule
          sides: [...]
          criteria: [...]
    - name: fuzzy_pass
      type: recon_unit
      operations:
        - name: fuzzy_amount
          behavior: always_suggest
          sides: [...]
          criteria: [...]
  cross_source_checks:
    - name: ap_balance
      ...
```

### 7b. Isolating parallel business streams (the default for multi-stream tasks)

When a task spans several **parallel** streams of the same business — e.g.
Swiggy vs Zomato orders, or each platform's bank-settlement recon — model each
stream as its **own nested `recon_unit` inside one config**. Do **not** emit one
file per stream.

This is safe because each stream anchors on disjoint `pool` values: the
engine's sequential claim-once consumption never cross-contaminates them, so
ordering between sibling streams is irrelevant. And it matters downstream — a
recon config is published to the numberlabs platform (via the API server MCP)
as a **single versioned document**, so splitting streams across files means a
later push captures only one of them and silently drops the rest (see the
`numberlabs-configs` skill).

```yaml
openrecon: v0.2.0
match:
  name: marketplace_recon
  operations:
    - name: swiggy_orders
      type: recon_unit                # nested unit — one business stream
      operations:
        - name: swiggy_match_order_to_pos
          behavior: auto_match
          sides:
            - name: swiggy_aggregator
              pick:
                - field: pool
                  op: equals
                  value: swiggy_order
              unit:
                kind: identity
            - name: swiggy_pos
              pick:
                - field: pool
                  op: equals
                  value: pos_swiggy
              unit:
                kind: identity
          criteria:
            - field: identifiers.order_id
              comparator: equals
              between: [swiggy_aggregator, swiggy_pos]
    - name: zomato_orders
      type: recon_unit                # second stream — disjoint pools, never cross-matches
      operations:
        - name: zomato_match_order_to_pos
          behavior: auto_match
          sides:
            - name: zomato_aggregator
              pick:
                - field: pool
                  op: equals
                  value: zomato_order
              unit:
                kind: identity
            - name: zomato_pos
              pick:
                - field: pool
                  op: equals
                  value: pos_zomato
              unit:
                kind: identity
          criteria:
            - field: identifiers.order_id
              comparator: equals
              between: [zomato_aggregator, zomato_pos]
```

**Name every rule and side uniquely across the whole tree** — prefix per stream
(`swiggy_aggregator`, `zomato_aggregator`, …). The spec requires global
uniqueness of `ReconUnit.name`, `Rule.name`, and `Side.name` for correct
`match_id` hashing. NOTE: the openrecon binary's `openrecon validate` does **not**
currently enforce this (colliding names pass) — author unique names anyway; it
is a conformance requirement, not a validation-caught one.

**`cross_source_checks` is top-level only.** Put balance controls on the
outermost `match:` unit; nested units reject them.

---

## Config invariants (caught before run)

| Violation | Error |
|---|---|
| `skip` with >1 side | config error |
| `skip` with criteria | config error |
| `SubsetSearch` on >1 side of same Rule | config error |
| `MatchCriterion.between` references undeclared side | config error |
| `ConnectedComponents.by` contains non-scalar path | config error |
| Side `pick` missing a pool anchor (`field: pool`, op `equals`/`in`) | config error — `side 'X' must scope by pool ...` |
| Pool anchor `op: equals` with a non-string value, or `op: in` with an empty/non-string list | config error |
| Cycle in `ReconUnit.operations` | config error |

---

## Edge cases

| Situation | Behaviour |
|---|---|
| Path resolves to `None` on either side of criterion | criterion does NOT hold |
| Bucket: `by` resolves to `None` | journal dropped from this side; stays in pool |
| SubsetSearch: no valid subset | no ResolutionItem; journals become unclaimed |
| `auto_match` with N > 1 candidates | `ResolutionItem(needs_selection)` — not consumed |
| ValidationRule fires | match recorded; validation ResolutionItem added |
| `Reject()` | journals return to pool; not consumed |

---

## Resolution actions

| Action | Valid on | Effect |
|---|---|---|
| `Confirm(index)` | `needs_confirmation`, `needs_selection` | Creates `Match(match_type='confirmed')` |
| `Reject()` | `needs_confirmation`, `needs_selection` | Journals return to pool |
| `Acknowledge()` | `validation_failure` | Marks as expected (audit) |
| `Override()` | `validation_failure` | Marks as approved exception (audit) |
| `ApplyTemplate(template, journal_id)` | `validation_failure` | Synthesizes corrective journal; triggers rerun |

---

## Config design checklist

1. List your pool labels (matches `JournalBlock.pool` from Task A: `"erp"`, `"bank"`, etc.) — every side's `pick` must anchor on one. Note `source` values too if you need refinements.
2. Identify the linking key — which `identifiers.*` field links records across pools?
3. Pick the amount path — which `entries[...]` expression gives the canonical amount per source?
4. Choose behavior — start with `auto_match`; use `always_suggest` where human review is needed.
5. Order rules by confidence — high-confidence rules first; fuzzy rules last.
6. Add `cross_source_checks` for balance controls (top-level `match:` unit only).
7. Wrap in nested `recon_unit` operations to isolate priority stages (exact → fuzzy).
8. If the task spans multiple independent business streams, model each as a
   nested `recon_unit` inside **one** config — not as separate files (see §7b).

---

## Worked examples

### 2-way ERP / Bank by UTR

```yaml
openrecon: v0.2.0
match:
  name: erp_bank_recon
  operations:
    - name: match_by_utr_exact
      behavior: auto_match
      sides:
        - name: erp
          pick:
            - field: pool
              op: equals
              value: erp
          unit:
            kind: identity
        - name: bank
          pick:
            - field: pool
              op: equals
              value: bank
          unit:
            kind: identity
      criteria:
        - field: identifiers.utr
          comparator: equals
          between: [erp, bank]
        - field:
            erp: "entries[account=\"AP\"].amount"
            bank: entries.amount
          comparator: within
          config:
            tolerance: "100"
          between: [erp, bank]
```

### Skip rule (consume internal transfers)

One operation (Rule) inside `match.operations`. Shown as a fragment:

```yaml
- name: skip_internal_transfers
  behavior: skip
  sides:
    - name: a
      pick:
        - field: pool
          op: equals
          value: erp
        - field: raw.type
          op: equals
          value: internal
```

### Self-validation (commission rate check)

```yaml
- name: commission_check
  behavior: auto_match
  sides:
    - name: a
      pick:
        - field: pool
          op: equals
          value: amazon
      unit:
        kind: identity
  validation:
    type: ratio_lte
    config:
      numerator: raw.commission
      denominator: raw.gross
      threshold: "0.15"
    flag: commission_overcharge
```
