---
name: numberlabs-runtime
description: Execute and inspect live numberlabs operations via the Flow Service API MCP server — recon runs and deep reads, data-actions and block-level debugging (incl. sandbox), refresh jobs, chart queries/materialization, and report generation. Trigger on recon run, run matches, unmatched, balance, diff, action, sandbox execute, action status, action exception, refresh, chart query, chart materialize, chart sql, report generate, report status, sources, freshness.
allowed-tools:
  - mcp__numberlabs
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh:*)
  - Read(${CLAUDE_PLUGIN_ROOT}/api/*)
---

# numberlabs-runtime skill

This skill covers triggering and inspecting runtime operations on your **live
numberlabs tenant** through the **Flow Service API MCP server**: recon runs and
their deep reads (`recon` toolset), data-actions and block-level debugging incl.
sandbox (`actions` toolset), refresh jobs and sources (`data` toolset), chart
queries and materialization (`charts` toolset), and report generation (`reports`
toolset). It does not cover config authoring or submission — use
`recon-authoring` (local) or `numberlabs-configs` (push to tenant) for those.

> **You are a customer in your own org.** Every tool call is scoped to your
> signed-in user's org (see `${CLAUDE_PLUGIN_ROOT}/api/AUTH.md`). For chart
> materialization or report generation, the relevant config must already be
> deployed (via `numberlabs-configs`).

---

## Activation cues

Use this skill when the user says any of: recon run, run matches, unmatched,
balance, diff, action, sandbox execute, action status, action exception, refresh,
chart query, chart materialize, chart sql, report generate, report status,
sources, freshness — and the intent is to run or inspect a live operation.

---

## Prerequisites

1. **MCP server connected.** The bundled `.mcp.json` connects to the numberlabs
   MCP server via `mcp-remote` with an OAuth 2.1 sign-in on first use. Point at
   staging/local by changing the URL to the matching `mcp_url` in
   `${CLAUDE_PLUGIN_ROOT}/defaults.json`. See `api/MCP.md` and `api/AUTH.md`.

2. **A deployed config** for chart/report/recon work (deploy via
   `numberlabs-configs`).

---

## Discovery first

Tools are named by their route's OpenAPI `operationId` and grouped into the
`recon`, `actions`, `charts`, `reports`, and `data` toolsets. Read a tool's entry
in the advertised list (`tools/list`) before first use — its input schema is the
source of truth. Load the concept pages below for semantics the schema can't
express (polling contracts, materialization ordering, SSE behaviour, template
constraints).

---

## Workflow

### Recon runs (`recon` toolset)

Trigger a recon run, then poll its status until terminal, then read results
(matches, unclaimed/unmatched, balance, diff, check-failures, unmatched-by) via
the deep-read tools. Each is a tool wrapping the corresponding recon-run route.

### Actions (`actions` toolset)

```
1. execute   — call the data-action execute tool (production) OR the sandbox
               execute tool (dry-run during authoring; ephemeral, no workflow id)
2. poll      — poll the action get_one tool until status is terminal:
               SUCCESS | PARTIAL | FAILED | CANCELLED   (interval 3–5s)
3. inspect   — on PARTIAL/FAILED, use the exception / block-errors tools
4. cancel    — only PENDING/PROCESSING/PARTIAL are cancellable
```

Use the **sandbox** action tools during config authoring/testing (results are
ephemeral); use the **data** action tools for production runs. See
`api/ACTIONS.md` for the data-vs-sandbox namespace and the polling contract.

### Refresh & sources (`data` toolset)

Trigger a refresh job, then poll its status until terminal. The `data` toolset
also covers sources and freshness, and refresh trigger / status / cancel.

### Charts (`charts` toolset)

Materialization must precede query:
```
1. materialize — call the chart-materialize tool, capture the status id
2. poll        — poll the materialize-status tool until COMPLETED (10–30s)
3. query       — only then call the saved-chart query tool, or the ad-hoc
                 chart-SQL tool (100-row cap) for exploratory queries
```
Querying before materialization completes returns `404 no_materialized_view` —
wait and retry, don't re-submit. See `api/CHARTS.md`.

### Reports (`reports` toolset)

Report generation is fire-and-forget: the submit tool enqueues the job and
returns an id; poll the report-status tool (the underlying route streams SSE, but
the MCP tool returns the resolved result) until `READY` or `FAILED`, then fetch
via the download tool. Templates pin `api_version: "template/v4"`. See
`api/REPORTS.md` for status progression and template constraints.

---

## Concept references

| Page | When to load |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/api/MCP.md` | Always — how tools are named/selected and how a call executes. |
| `${CLAUDE_PLUGIN_ROOT}/api/AUTH.md` | Always — token model, OAuth, scopes, org scoping. |
| `${CLAUDE_PLUGIN_ROOT}/api/ACTIONS.md` | Executing actions, polling, exceptions, cancel, sandbox vs data. |
| `${CLAUDE_PLUGIN_ROOT}/api/CHARTS.md` | Chart configs, ad-hoc SQL, materialization ordering. |
| `${CLAUDE_PLUGIN_ROOT}/api/REPORTS.md` | Report templates and generation jobs. |

For recon-run and refresh resource shapes, read the tool's input schema in the
advertised list — those are not in the concept catalog.

---

## Failure modes

| Symptom | Cause | Recovery |
|---|---|---|
| `401` on a tool call | Token missing/expired/revoked | Re-connect the MCP server (re-run OAuth). Persistent 401 = account not provisioned; contact numberlabs. |
| `403 insufficient_scope` | Authenticated but lacking the route's scope | Scopes must be widened by numberlabs; re-auth won't help. |
| Action stuck in PROCESSING | Worker stalled or exception not surfaced | Load `api/ACTIONS.md`; use the exception tool; cancel if needed. |
| `400 INVALID_TRANSITION` on cancel | Action already terminal | Nothing to cancel; inspect results. |
| `404 no_materialized_view` on chart query | Materialization not finished | Wait ~60s and retry; only re-materialize if status is FAILED. |
| Report status not progressing | Report worker stalled | Load `api/REPORTS.md`; check status, cancel if available. |
| `422` on report add/edit | Wrong `api_version` or csv-with-multiple-visible-sheets | Set `api_version:"template/v4"`; keep ≤1 visible sheet when csv is allowed. |
| `404` (not found) | Wrong action/job/chart/report id | Use the relevant list/get tool to confirm the id. |
