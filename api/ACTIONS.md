> **What this page is.** The advertised MCP tool list gives you each action tool's input schema, but it cannot express the *polling contract* after execute, the cancellation transitions, or the `data` vs `sandbox` namespace distinction. This page is the durable reference for those. The endpoints below live in the `actions` toolset; if a tool for one of them is not in the advertised list, it is not part of the curated 64-tool MCP surface — ask your numberlabs contact.

# ACTIONS — Execution Contract and Lifecycle Endpoints

For `get_one`, `get` (list), `execute`, `triggerStop`, block output, and the sandbox execute / sandbox block-output routes, read the corresponding `actions` tool's input schema from the advertised list (and the API reference). The three routes detailed below carry behaviour the tool schemas alone cannot describe.

---

## `data` vs `sandbox` namespace

The `data` namespace persists results to the org's data lake and ties the action to a deployed workflow ID. The `sandbox` namespace runs against a caller-supplied session snapshot; results are ephemeral, no workflow ID is created, and output tables are cleaned up after the session ends.

Use the `sandbox/execute` tool during config authoring and testing. Use the `data/execute` tool for production runs.

---

## Polling contract after execute

Both the `data/execute` and `sandbox/execute` tools return immediately with `action_id` and `status: "PENDING"`. Poll the tool wrapping `POST /api/actions/data/get_one` (or inspect `sandbox` output directly) until `status` is one of:

- `SUCCESS` — completed with no row-level failures.
- `PARTIAL` — completed but some rows failed matching/processing.
- `FAILED` — execution halted with a fatal error.
- `CANCELLED` — stopped via the `triggerStop` tool.

Recommended poll interval: 3–5 seconds. Do not re-submit; poll the returned `action_id`.

---

## `POST /api/actions/data/download_exception`

**Purpose:** Retrieve exception and error log entries for a completed or failed data action.

**Toolset:** `actions`. Call the tool wrapping `POST /api/actions/data/download_exception` with body:

```json
{ "action_id": "<action-uuid>" }
```

**Response (2xx):**
```json
{
  "exceptions": [
    {
      "timestamp": "2025-01-15T10:31:00Z",
      "status": "ERROR",
      "detailed_status": "Row 42: amount column is null",
      "block_id": "<block-uuid>"
    }
  ]
}
```

Returns log entries where `status` is `ERROR`, `WARNING`, or `PROCESSING_OVER_FAILURE`.

**Errors:**
- `404` — action not found.
- `500` — storage retrieval failure.

---

## `GET /api/actions/data/{action_id}/blocks/{block_id}/errors`

**Purpose:** Return paginated error rows for a specific block — rows that were routed to the failure output.

**Toolset:** `actions`. Call the tool wrapping `GET /api/actions/data/{action_id}/blocks/{block_id}/errors`, substituting the action and block UUIDs, with these query arguments:
- `page_number` — page index (1-based), integer, optional (default 1).
- `length` — rows per page, integer, optional (default 20).

**Response (2xx):**
```json
{
  "data": [
    { "amount": null, "currency": "USD", "_error": "amount column is null" }
  ],
  "total_rows": 2,
  "total_pages": 1,
  "page_number": 1,
  "block_id": "<block-uuid>",
  "parent_block_id": null
}
```

**Errors:**
- `404` — action, block, or error table not found.

---

## `POST /api/actions/{action_id}/delete`

**Purpose:** Trigger asynchronous deletion of an action and its associated stored files.

**Toolset:** `actions`. Call the tool wrapping `POST /api/actions/{action_id}/delete`, substituting the action UUID. No body.

**Response (2xx):**
```json
{
  "delete_action_id": "<delete-action-uuid>",
  "target_action_id": "<action-uuid>",
  "workflow_id": "<workflow-uuid>",
  "message": "Delete workflow started"
}
```

Deletion is asynchronous — the response confirms the delete workflow was submitted, not that files are already removed. The target action must be of type `file` and in status `SUCCESS`, `PARTIAL`, or `REFRESHED`. Draft or in-progress actions must be cancelled first.

**Errors:**
- `404` — target action not found (`ACTION_NOT_FOUND`).
- `409` — action type is not `file` (`INVALID_ACTION_TYPE`) or status does not allow deletion (`INVALID_ACTION_STATE`).
- `400` — other request errors.

---

## Authoring notes

**Cancellation semantics.** Only actions in `PENDING`, `PROCESSING`, or `PARTIAL` states can be cancelled. A `400 INVALID_TRANSITION` response means the action has already reached a terminal state. Cancellation is best-effort — in-flight processing tasks may complete before the signal propagates.

**Delete cascade.** Deletion removes the action record and all associated file artifacts from blob storage. It does not affect the deployed canvas configuration.
