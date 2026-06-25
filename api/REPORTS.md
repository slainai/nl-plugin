> **What this page is.** The advertised MCP tool list gives you each report tool's input schema, but it cannot express the `template/v4` *schema constraints*, the report-status *streaming behaviour*, or the fire-and-forget submission pattern. This page is the durable reference for those. The endpoints below live in the `reports` toolset; if a tool for one of them is not in the advertised list, it is not part of the curated 64-tool MCP surface — ask your numberlabs contact.

# REPORTS — Template Constraints and Generation Lifecycle

For template retrieval, deletion, and the report generation/download routes, read the corresponding `reports` tool's input schema from the advertised list (and the API reference). The three routes detailed below, plus the constraints and lifecycle behaviour, cover what the tool schemas alone cannot describe.

---

## `template/v4` schema constraints

- `api_version` must be the **literal string `"template/v4"`**. Any other value (including omitting the field) returns `422`. When adapting configs from older environments, update `api_version` explicitly.
- `sheet_type` is `"normal"` or `"hidden"`. Hidden sheets appear in `xlsx` output but are invisible to end users. They do **not** appear in `csv` or `json` exports.
- If `"csv"` is in `allowed_formats`, the template must have at most **one visible (non-hidden) sheet**. Multiple visible sheets with CSV format returns `400`.
- `json` exports produce a nested object with one key per sheet name.

---

## Report-status behaviour (`GET /api/report/status`)

The underlying status route streams Server-Sent Events; the stream closes automatically when `report_status` reaches `READY` or `FAILED`. You do **not** stream it yourself. Call the **status tool** in the `reports` toolset (wrapping `GET /api/report/status`) with the report-status id — the MCP layer drives the underlying request in-process and returns the resolved result. If the status is not yet terminal, poll the tool again rather than holding a stream open.

Underlying cadence: events arrive every ~3 seconds. `report_status` progression: `PENDING` -> `RUNNING` -> `READY` (or `FAILED`). Maximum stream duration is 15 minutes — if a report has not reached `READY`/`FAILED` within that window, treat it as a failure and re-submit.

**Retrieving the generated file.** When `READY`, `report_url` is an internal storage path — do not fetch it directly. Use the download tool in the `reports` toolset (read its input schema from the advertised list) to retrieve the file.

---

## Fire-and-forget pattern

The submit tool (wrapping `POST /api/report`) enqueues the job and returns `202` with `_id` immediately. Do not call the submit tool again. Poll the status tool with `id=<_id>` right after submission to track progress to `READY`/`FAILED`.

---

## `POST /api/reports/add`

**Purpose:** Create a new report template defining sheets, queries, and export formats.

**Toolset:** `reports`. Call the tool wrapping `POST /api/reports/add` with body:

```json
{
  "title": "Q1 Bank Reconciliation Summary",
  "description": "Matched and unmatched transactions for Q1",
  "api_version": "template/v4",
  "template_config": {
    "sheets": [
      {
        "sheet_name": "Matched",
        "sheet_type": "normal",
        "queries": [
          {
            "title": "Matched Transactions",
            "show_title_row": true,
            "query": "SELECT ref, amount, currency FROM matched_txns WHERE org_id = :org_id",
            "table_ending_spaces": 2
          }
        ]
      }
    ],
    "allowed_formats": ["xlsx", "json"]
  }
}
```

**Response (2xx):**
```json
{
  "template_id": "<template-uuid>",
  "title": "Q1 Bank Reconciliation Summary",
  "api_version": "template/v4",
  "created_at": "2025-01-15T10:00:00Z"
}
```

**Errors:**
- `400` — `csv` in `allowed_formats` with multiple visible sheets; other business rule violations.
- `422` — wrong `api_version`, missing required fields, extra fields.

---

## `POST /api/reports/edit`

**Purpose:** Replace an existing report template's configuration entirely (full replace, no partial patch).

**Toolset:** `reports`. Call the tool wrapping `POST /api/reports/edit` with the same body shape as `POST /api/reports/add`, plus `"template_id": "<template-uuid>"` at the top level.

**Response (2xx):**
```json
{
  "template_id": "<template-uuid>",
  "title": "Q1 Bank Reconciliation Summary (Rev 2)",
  "updated_at": "2025-01-16T09:00:00Z"
}
```

**Errors:**
- `400` — `csv` format with multiple visible sheets; other business rule violations.
- `404` — template not found.
- `422` — schema validation failure.

---

## `GET /api/metadata/reports`

**Purpose:** List all report templates for the authenticated org — metadata only, without full `template_config` payloads.

**Toolset:** `reports`. Call the tool wrapping `GET /api/metadata/reports` (no arguments).

**Response (2xx):** Array of `{ template_id, title, description, api_version, created_at }` — no `template_config` payloads.

**Errors:**
- `500` — storage retrieval failure.
