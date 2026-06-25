> **What this page is.** The advertised MCP tool list gives you each chart tool's input schema, but it cannot express the *materialization-must-precede-query ordering* or that chart update is a full replace. This page is the durable reference for those. The endpoints below live in the `charts` toolset; if a tool for one of them is not in the advertised list, it is not part of the curated 64-tool MCP surface — ask your numberlabs contact.

# CHARTS — Materialization Contract and Update Semantics

For chart CRUD (`create`, `get`, `delete`), the materialize submit + status, and the ad-hoc SQL route, read the corresponding `charts` tool's input schema from the advertised list (and the API reference). The two routes detailed below carry behaviour the tool schemas alone cannot describe.

---

## Materialization-must-precede-query ordering

Chart queries run against a pre-materialized view. The required sequence is:

1. Call the **materialize tool** (wrapping the chart-materialize submit route) for the `chart_id`, and capture the returned `status_id`.
2. Poll the **materialize-status tool** for that `status_id` until `status` is `COMPLETED` (interval: 10–30 seconds).
3. Only then call the tool wrapping `POST /api/chart`, or the ad-hoc chart-SQL tool.

If you call the `POST /api/chart` tool before materialization completes, the server returns `404` with error key `no_materialized_view` (surfaced through the tool result). Wait 60 seconds and retry — do not re-submit the materialization job unless `status` is `FAILED`.

---

## `POST /api/charts/update`

**Purpose:** Update an existing chart configuration by ID (full replace, not a partial patch).

**Toolset:** `charts`. Call the tool wrapping `POST /api/charts/update` with body:

```json
{
  "chart_id": 42,
  "title": "Monthly Match Rate (Updated)",
  "query": "SELECT month, match_rate, total FROM recon_summary",
  "type": "bar",
  "post_query": null,
  "is_multiple_series": false,
  "series_fields": [],
  "chart_config": {}
}
```

All fields except `chart_id` follow the same semantics as the chart create tool (`POST /api/charts/create`). The update is a **full replace** — provide the complete desired state.

**Response (2xx):**
```json
{
  "id": 42,
  "title": "Monthly Match Rate (Updated)",
  "query": "SELECT month, match_rate, total FROM recon_summary",
  "type": "bar",
  "updated_at": "2025-01-16T09:00:00Z"
}
```

**Errors:**
- `400` — validation failure (empty title or query).
- `404` — chart ID not found.

---

## `POST /api/chart`

**Purpose:** Execute a saved chart's query against its pre-materialized view and return structured result data including `chartConfig` and `series` fields for display.

**Toolset:** `charts`. Call the tool wrapping `POST /api/chart` with body:

```json
{
  "chartid": "42",
  "dateRange": {
    "start_date": "2025-01-01",
    "end_date": "2025-03-31"
  }
}
```

`chartid` is the chart's string identifier (same `id` returned from CRUD, coerced to string). `dateRange` is optional; omit or pass `{}` to query the full available range.

**Distinction from the ad-hoc chart-SQL tool:** the `POST /api/chart` tool renders a *saved* chart with its configured metadata and returns the `chartConfig`+`series` fields needed for display. Use the ad-hoc chart-SQL tool for one-off exploratory queries with no chart config association (100-row cap).

**Response (2xx):**
```json
{
  "chart_id": "42",
  "title": "Monthly Match Rate",
  "data": [
    {"month": "2025-01", "match_rate": 0.987},
    {"month": "2025-02", "match_rate": 0.991}
  ],
  "type": "line",
  "chartConfig": {"xAxis": "month", "yAxis": "match_rate"},
  "series": null,
  "isMultipleSeries": false,
  "seriesFields": []
}
```

**Errors:**
- `404` — chart config not found, or materialized view not yet built (`no_materialized_view`); retry after 60 seconds once materialization completes.
- `500` — query execution failure.
