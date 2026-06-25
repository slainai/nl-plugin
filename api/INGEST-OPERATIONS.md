> **What this page is.** The advertised MCP tool list gives you each mutation tool's input schema, but it cannot express the *optimistic-concurrency contract*, the undo/redo scope, bulk atomicity, or how a file upload flows through a tool. This page is the durable reference for those. The endpoints below live in the `authoring` (and, for upload, `data`/`authoring`) toolset; if a tool for one of them is not in the advertised list, it is not part of the curated 64-tool MCP surface — ask your numberlabs contact.

# IngestConfig Operations — Mutation Endpoints and Concurrency Contract

For the single-operation `POST /{id}/operations` route, read the corresponding `authoring` tool's input schema from the advertised list (and the API reference). The four routes below carry behaviour the tool schemas alone cannot describe.

---

## Optimistic concurrency contract

Every mutating call (single operation, undo, redo, bulk, upload) accepts an `expected_parent_operation_id` field. The server rejects with `409 Conflict` if `HEAD` has advanced since the client last read the config. That `409` surfaces through the tool result exactly as over HTTP (see `MCP.md`).

**Workflow:**
1. After each successful operation, capture the returned `operation_id` as your local `head_operation_id`.
2. Pass it as `expected_parent_operation_id` on the next call.
3. On `409`: re-read the config via the tool wrapping `GET /api/ingest-configs/{id}`, read the new `head_operation_id`, reconcile your intended change, then retry.
4. Pass `null` as `expected_parent_operation_id` only for the very first operation on a fresh draft (HEAD is null).

---

## `POST /api/ingest-configs/{ingest_config_id}/undo`

**Purpose:** Reverse the most recent active operation at HEAD, marking it inactive in the chain.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/{ingest_config_id}/undo` with body `{}`.

**Response (200):** `OperationResponse` for the undone operation, with `is_active: false`.

**Errors:**
- `409` — concurrent modification conflict.
- `400` — no active operations remain to undo.

---

## `POST /api/ingest-configs/{ingest_config_id}/redo`

**Purpose:** Re-apply the most recently undone operation, making it active again.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/{ingest_config_id}/redo` with body `{}`.

**Response (200):** `OperationResponse` for the re-applied operation, with `is_active: true`.

**Errors:**
- `400` — no undone operations available to redo, or a new operation was applied after the undo (redo stack cleared).

---

## `POST /api/ingest-configs/{ingest_config_id}/operations/bulk`

**Purpose:** Apply multiple operations as a single atomic, reversible BULK compound — one HEAD advance; one undo reverses all sub-operations together.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/{ingest_config_id}/operations/bulk` with body:

```json
{
  "operations": [
    {
      "operation_type": "INSERT",
      "block_id": "b1000000-0000-0000-0000-000000000002",
      "data": {"block_type": "transform", "name": "normalise_amounts", "config": {}}
    },
    {
      "operation_type": "INSERT",
      "block_id": "b1000000-0000-0000-0000-000000000003",
      "data": {"block_type": "output", "name": "journal_output", "config": {}}
    }
  ],
  "expected_parent_operation_id": "op-uuid-of-current-head"
}
```

Sub-operations are executed in array order. Per-sub-op `expected_parent_operation_id` is ignored — concurrency is controlled solely by the top-level field. If block B depends on block A (e.g. an edge A→B), INSERT A before B in the array. The server rejects the entire batch on the first sub-op failure; no partial state is written.

**Response (200):** `{ "success": true, "total_operations": N, "successful_operations": N, "failed_operations": 0, "operations": [{operation_id, operation_type, block_id, is_active}], "session": {ingest_config_id} }`

**Errors:**
- `409` — `expected_parent_operation_id` does not match HEAD.
- `400` — any sub-operation fails validation; entire batch rejected.

---

## `POST /api/ingest-configs/{ingest_config_id}/blocks/{block_id}/upload`

**Purpose:** Upload a lookup data file (CSV) to a lookup-type block, creating an UPDATE operation that increments the block's file version.

**Toolset:** `data`/`authoring`. This route takes a `multipart/form-data` body with fields:
- `file` — the CSV file (required).
- `expected_parent_operation_id` — form field (string, optional) for optimistic concurrency.

You do not compose the multipart payload yourself. If this route is exposed, it appears as an **upload tool** in the advertised list; pass the file (and the optional `expected_parent_operation_id`) as that tool's arguments. The MCP layer replays the request in-process — building the multipart body and forwarding your bearer token — and returns the result. There is no local token file and no curl involved. Read the upload tool's input schema for the exact argument names it expects for the file and concurrency fields.

**Response (200):** `{ "success": true, "operation_id": "...", "block_id": "...", "file_version": 2, "file_name": "lookup_table.csv" }`

**Errors:**
- `409` — `expected_parent_operation_id` mismatch.
- `400` — block is not a lookup type, or the config is not an active draft.

---

## Authoring notes

**Undo/redo scope.** Undo is scoped to the current draft's operation chain and cannot cross the boundary into the parent (deployed) config. To revert to the parent state entirely, use the `end` tool with `action: "discard"` and start a fresh draft.

**Prefer undo/redo for interactive correction.** Undo/redo are cheaper than issuing a corrective DELETE/INSERT. However, applying any new operation after an undo clears the redo stack — redo is not available after forward progress resumes.
