---
name: numberlabs-configs
description: Submit and manage match-configs, identifier-configs, and ingest-config sessions on your live numberlabs tenant via the Flow Service API MCP server (authoring toolset), including bulk desired-state authoring from a full document. Trigger on submit config, publish config, deploy config, match config, identifier config, ingest config, from-document, bulk replace, desired state, replace identifier types, ingest session, draft, op, deploy lock, ingest validate, ingest deploy, push to platform, push to tenant.
allowed-tools:
  - mcp__numberlabs
  - Bash(openrecon validate:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh:*)
  - Read(${CLAUDE_PLUGIN_ROOT}/api/*)
  - Read(${CLAUDE_PLUGIN_ROOT}/grammars/*)
---

# numberlabs-configs skill

This skill covers pushing locally-validated configs to your **live numberlabs
tenant** and managing the full ingest-config session lifecycle — match-configs,
identifier-configs, and ingest-config sessions (open, ops, validate, deploy) —
through the **Flow Service API MCP server** (the `authoring` toolset). It does
not cover recon runs, actions, charts, reports, or refresh — use the
`numberlabs-runtime` skill for those. Authoring configs locally (before you push
anything) is the `recon-authoring` skill.

> **You are a customer in your own org.** Every tool call is scoped to the org
> your signed-in user belongs to (see `${CLAUDE_PLUGIN_ROOT}/api/AUTH.md`). This
> skill assumes that org already exists — there is no org-creation or
> user-management here.

---

## Activation cues

Use this skill when the user says any of: submit / publish / deploy a config,
match config, identifier config, ingest config, from-document, bulk replace,
desired state, replace identifier types, ingest session, draft, op, deploy lock,
ingest validate, ingest deploy, "push to the platform / tenant" — and the intent
is to push or manage a config on the live server.

**Decision: which path?**
- "Publish / replace a full config from a YAML" → from-document path
  (preferred — atomic, one tool call).
- "Edit one rule / add one identifier type to an existing draft" → per-op path
  (ingest-config session).

---

## Prerequisites

1. **MCP server connected.** This plugin ships an `.mcp.json` that connects to
   the numberlabs MCP server (`https://api.numberlabs.io/mcp`) via `mcp-remote`.
   On first use it runs an OAuth 2.1 sign-in in your browser; the credential is
   cached. To point at staging/local, change the URL to the matching `mcp_url`
   in `${CLAUDE_PLUGIN_ROOT}/defaults.json`. See
   `${CLAUDE_PLUGIN_ROOT}/api/MCP.md` and `api/AUTH.md`.

2. **`openrecon` binary** for the mandatory local validate gate:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/install-openrecon.sh
   openrecon --version
   ```

---

## Discovery first

The MCP tools are named by their route's OpenAPI `operationId` and grouped into
the `authoring` toolset. Before using a tool you haven't called before, read its
entry in the **advertised tool list** (`tools/list`) — its input schema is the
source of truth for the body shape. For semantics the schema can't express
(state machines, concurrency, deploy locks), load the concept pages below.

---

## Workflow

### From-document path (preferred for bootstrap / full replace)

Three resources accept a complete desired-state document in a single tool call.
The server expands the document into ordered ops and applies them atomically —
no draft management, no per-op loop. These map to tools in the `authoring`
toolset wrapping the corresponding routes:

| Resource | Semantics | Notes |
|---|---|---|
| `identifier-types` | Replace-all for identifier types (`PUT`) | Body `{user_id, types:[{slug,name,format_regex?}], publish}`. Empty `types` clears all. |
| `match-config-document` | Create a new match draft from a YAML/JSON tree | `recon_units` required; `publish: true` publishes. Whole-document replace — must contain **all** streams (see warning). |
| `ingest-pipeline` | Create a new ingest draft from a pipeline doc | `pipeline.blocks` required; `publish: true` deploys. |

> **`match-config-document` is whole-document, versioned desired state — not an
> additive patch.** Its `recon_units` is a flat list (one entry per stream;
> locally-nested `recon_unit`s flatten to multiple top-level entries here). On
> `publish: true` the pushed document *becomes* the new live config — anything
> not in it is dropped. The file you push must already contain **all** streams
> you want live. **Never publish a per-stream fragment over a multi-stream live
> config** — author parallel streams as one combined config (see
> `recon-authoring` / `RECON.md` §7b) and push the whole document.

Flow:
```
1. local validate  — openrecon validate <config> --identifiers identifiers.json --format json
                     MANDATORY gate. Never call an MCP tool before a clean local validate.
                     --identifiers is required for any config with a top-level `blocks` key
                     (ingest-config / blocks-JSON); match-only configs omit it.
2. submit          — call the authoring tool for the resource, passing the
                     document as the request body (read its input schema first).
                     `publish: true` in the body publishes/deploys atomically.
3. on error        — see Failure modes below
```

### Per-op path (surgical edits to an existing config)

Use the ingest-config session surface when editing one thing at a time on an
existing draft:

```
1. local validate  — openrecon validate <config> --identifiers identifiers.json --format json
2. open / resume   — call the create-ingest-config tool (or resume an existing draft)
3. apply ops       — call the single-operation tool; carry the optimistic-
                     concurrency token between calls (see INGEST-OPERATIONS.md)
4. server validate — call the validate tool until it returns valid:true
5. deploy          — call the deploy tool for the session
6. on error        — see Failure modes below
```

The per-op `op` body is loosely typed in OpenAPI, so the advertised schema may
not enumerate the `op_type` values. For identifier-config they are
`add_type | remove_type | update_type` with
`{op_type, value:{slug, name, format_regex?}}`. For non-trivial edits prefer the
from-document path.

**Two-gate validate ordering** (mandatory before every deploy): the local
`openrecon validate` catches structural/grammar errors; the server-side validate
tool catches cross-block and cross-config constraints. Both gates must pass — see
`api/INGEST-VALIDATE-DEPLOY.md`.

**Op concurrency:** only one op applies to a session at a time, gated by an
optimistic-concurrency token. On a `409` conflict, re-read the config, reconcile,
and retry — see `api/INGEST-OPERATIONS.md`.

---

## Concept references

| Page | When to load |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/api/MCP.md` | Always — how tools are named/selected and how a call executes. |
| `${CLAUDE_PLUGIN_ROOT}/api/AUTH.md` | Always — token model, OAuth, scopes, org scoping. |
| `${CLAUDE_PLUGIN_ROOT}/api/INGEST-LIFECYCLE.md` | Creating or managing an ingest-config session (open, resume, end, save). |
| `${CLAUDE_PLUGIN_ROOT}/api/INGEST-OPERATIONS.md` | Applying ops, undo/redo, bulk edits, uploading lookup files within an open session. |
| `${CLAUDE_PLUGIN_ROOT}/api/INGEST-VALIDATE-DEPLOY.md` | Server-side validate, deploy, diff, deploy-lock management. |

For match-config and identifier-config resource shapes, read the tool's input
schema in the advertised list — those are not in the concept catalog.

---

## Failure modes

| Symptom | Cause | Recovery |
|---|---|---|
| `401` on a tool call | Token missing/expired/revoked | Re-connect the MCP server (re-run OAuth). Persistent 401 after sign-in = account not provisioned; contact numberlabs. |
| `403 insufficient_scope` | Authenticated but lacking the route's scope | Your account's scopes must be widened by numberlabs; re-auth won't help. |
| `409` on deploy | Deploy lock held by another session | See `api/INGEST-VALIDATE-DEPLOY.md` for the lock fields; release/wait or `force:true` only if stale. |
| `409` on ingest op | Optimistic-concurrency conflict | Re-read the config, reconcile, retry — see `api/INGEST-OPERATIONS.md`. |
| `422` on submit | Body shape incorrect | Re-read the tool's input schema and fix the structure. |
| Server validate fails after local validate passed | Remote caught cross-block / cross-config constraints | Load `api/INGEST-VALIDATE-DEPLOY.md`; fix locally, re-submit. |
| `404` (not found) | Wrong resource ID or stale reference | Use the list tool for the resource to confirm the ID. |
| `400` with `detail.message` | Single application-level error (duplicate slug, unknown source) | Read `detail.message` — it usually includes a JSON-pointer position (`types[1]`). Fix and resubmit. |
| `400` with `detail.field_errors` | Multiple field-level failures | Iterate over `field_errors` keyed by JSON pointer (e.g. `/recon_units/0/rules/1/slug`). |
