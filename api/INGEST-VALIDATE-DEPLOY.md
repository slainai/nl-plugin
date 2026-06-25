> **What this page is.** The advertised MCP tool list gives you the validate, deploy, lock, and diff tools' input schemas, but it cannot express the *two-gate validation ordering*, the deploy-lock polling pattern, or the schema-inference behaviour. This page is the durable reference for those. The endpoints below live in the `authoring` toolset; if a tool for one of them is not in the advertised list, it is not part of the curated 64-tool MCP surface — ask your numberlabs contact.

# IngestConfig Validate & Deploy — Validation, Deploy Lock, and Constraints

For the deploy route, the lock GET route, and deployment-history routes, read the corresponding `authoring` tool's input schema from the advertised list (and the API reference). The three routes detailed below carry behaviour the tool schemas alone cannot describe.

---

## Two-gate validation ordering

**Must follow this sequence before every deploy:**

1. `openrecon validate <config-file> --identifiers <spec.json>` — **local** structural validation (grammar, required fields, block types) plus identifier-subset check (every key used by a journal block's `args.identifiers` / `args.primary_identifier` must appear in the spec's flat `{"identifiers": [...]}` list). `--identifiers` is required for configs containing a top-level `blocks` key. Catches errors offline, with no network round-trip and no auth (see `AUTH.md`).
2. The MCP **validate tool** wrapping `POST /api/ingest-configs/{id}/validate` — remote semantic validation (cross-block schema propagation, cyclic DAG detection, expression evaluation against inferred column types). Must return `"valid": true`.
3. The MCP **deploy tool** — deploy. It is rejected if step 2 was not run or returned errors.

Never skip either gate. The local `openrecon` validator cannot detect cross-block reference errors. The remote validator cannot catch grammar violations in config files it has not yet received.

---

## Deploy-lock polling pattern

The deployment lock is **org-wide and exclusive** — only one deploy can run at a time. The server acquires the lock when the deploy tool is called and releases it automatically when the Temporal workflow completes (not on the tool's response return). The tool returns before the workflow finishes.

**To wait for a lock to clear:** poll the tool that wraps the lock `GET` route (the `authoring` tool for the ingest deploy lock) and inspect its fields:

- `locked` — when `false`, the lock is clear and you may deploy.
- `locked_by` — who currently holds it.
- `expires_at` — when the current lock lapses.

Poll on roughly a 5-second cadence until `locked` is `false`.

If `expires_at` is in the past, the lock is stale (the deploy workflow crashed mid-flight). Re-run the deploy tool with `"force": true` in its arguments to override the stale lock. Do not use `force` while a legitimate deploy is in progress.

---

## `POST /api/ingest-configs/{ingest_config_id}/validate`

**Purpose:** Run server-side validation — schema coherence, cross-block references, expression correctness.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/{ingest_config_id}/validate`, substituting the draft's UUID, with body:

```json
{ "validation_level": "full" }
```
`validation_level` — `"schema"` (structural only), `"reference"` (cross-block linkage), or `"full"` (all). Default: `"full"`.

**Response (200):**
```json
{
  "valid": true,
  "validation_level": "full",
  "errors": [],
  "warnings": [
    {
      "block_id": "b1000000-0000-0000-0000-000000000002",
      "error_type": "reference",
      "message": "Block references a column that may be absent at runtime",
      "details": {"column": "fx_rate"}
    }
  ],
  "validated_at": "2026-05-06T10:15:00Z"
}
```

Each item in `errors`/`warnings`: `block_id`, `error_type` (`"schema"` | `"reference"` | `"expression"`), `message`, `details`. A non-empty `errors` array blocks deploy.

**Errors:**
- `404` — config not found.
- `400` — validation request malformed.

---

## `GET /api/ingest-configs/{ingest_config_id}/diff`

**Purpose:** Return the set of operations and block-level changes between this config and its parent.

**Toolset:** `authoring`. Call the tool wrapping `GET /api/ingest-configs/{ingest_config_id}/diff`, substituting the config's UUID (draft or deployed).

**Response (200):** `{ "ingest_config_id", "parent_ingest_config_id", "operations_count", "operations": [{operation_id, operation_type, block_id, is_active, timestamp, user_id, success, data}], "added_blocks": [...], "modified_blocks": [...], "deleted_blocks": [...] }`

**Errors:**
- `404` — config not found.

---

## `GET /api/ingest-configs/{ingest_config_id}/blocks/{block_id}/output-schema`

**Purpose:** Infer and return the output column schema produced by a block given the current DAG state — useful for validating downstream config before applying operations.

**Toolset:** `authoring`. Call the tool wrapping `GET /api/ingest-configs/{ingest_config_id}/blocks/{block_id}/output-schema`, substituting the config and block UUIDs.

**Response (200):**
```json
{
  "block_id": "b1000000-0000-0000-0000-000000000001",
  "columns": [
    {"name": "transaction_id", "type": "string",  "nullable": false},
    {"name": "amount",         "type": "decimal", "nullable": false},
    {"name": "date",           "type": "date",    "nullable": true}
  ]
}
```

**Errors:**
- `404` — config or block not found (`SESSION_NOT_FOUND` / `BLOCK_NOT_FOUND`).
- `400` — schema inference failed (upstream block has an unresolvable expression — `SCHEMA_INFERENCE_FAILED` / `ExecutionOrderError`).
