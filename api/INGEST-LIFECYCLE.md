> **What this page is.** The advertised MCP tool list (`tools/list`) gives you each tool's name and input schema, but it cannot express the *draft session state machine* or the ordering rules around it. This page is the durable reference for those. The endpoints below are session-control routes in the `authoring` toolset; if a tool for one of them is not in the advertised list, it is not part of the curated 64-tool MCP surface — ask your numberlabs contact.

# IngestConfig Lifecycle — Session Endpoints and State Machine

For the routine `create`, `get`, `list`, `submit`, and `deploy` operations, read the corresponding `authoring` tool's input schema from the advertised tool list (and the API reference). The four session-control routes below cover behaviour the tool schemas alone cannot describe.

---

## Session state machine

```
(initial) ──create──> active ──end(save)──> inactive
                  ↑                 └──end(discard)──> abandoned
                  └─────resume──────────────────────┘ (active only)
```

- A config is created in `state: "active"`.
- `end` with `action: "save"` marks it `inactive` (blocks/operations preserved, ready to deploy after `save` annotates it).
- `end` with `action: "discard"` rolls back to parent state and marks the config `abandoned`.
- `resume` returns an `active` draft — use it at the start of a new session rather than creating a fresh config.
- A draft that is never ended stays `active` indefinitely. Always call `end` when done to keep the org's draft list clean.

---

## `GET /api/ingest-configs/current`

**Purpose:** Return the caller's current active draft, creating one from the deployed config if none exists.

**Toolset:** `authoring`. Call the tool wrapping `GET /api/ingest-configs/current` (no arguments).

**Response (200):** `IngestConfigResponse` — same shape as the create tool's output.

**Errors:**
- `400` — no deployed config exists and a draft cannot be seeded.

---

## `POST /api/ingest-configs/resume`

**Purpose:** Resume editing a specific draft by ID, or retrieve/create the caller's default draft when no ID is supplied.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/resume` with body:

```json
{ "ingest_config_id": "a1b2c3d4-0000-0000-0000-222222222222" }
```
`ingest_config_id` is optional. Omit it to get the same behaviour as the `current` tool.

**Response (200):** `IngestConfigResponse` with `state: "active"`.

**Errors:**
- `404` — the specified config does not exist.
- `400` — config is not in a resumable state (e.g. already deployed).

---

## `POST /api/ingest-configs/{ingest_config_id}/end`

**Purpose:** Close the editing session — either saving the draft or discarding all uncommitted changes.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/{ingest_config_id}/end`, substituting the draft's UUID for `{ingest_config_id}`, with body:

```json
{ "action": "save" }
```
`action` — `"save"` (mark inactive, keep blocks) or `"discard"` (roll back to parent state).

**Response (200):**
```json
{ "success": true, "ingest_config_id": "...", "action": "save" }
```

**Errors:**
- `404` — config not found.
- `400` — invalid action value or config already inactive.

---

## `POST /api/ingest-configs/{ingest_config_id}/save`

**Purpose:** Stamp deployment metadata (title + description) onto a draft before deploying.

**Toolset:** `authoring`. Call the tool wrapping `POST /api/ingest-configs/{ingest_config_id}/save`, substituting the draft's UUID, with body:

```json
{
  "title": "May reconciliation update",
  "description": "Adds three new lookup blocks for FX rates"
}
```
`title` — required, 1–32 characters. `description` — optional, max 256 characters.

**Response (200):**
```json
{ "success": true, "ingest_config_id": "...", "title": "May reconciliation update", "description": "..." }
```

**Errors:**
- `404` — config not found.
- `500` — persistence failure.

**Note:** the save route writes only deployment metadata — it does not flush blocks or operations. Block state is persisted immediately when each operation is applied. Call the save tool before the deploy tool if you want a human-readable label on the deployment history entry.

---

## Authoring notes

**create vs resume.** Call the `authoring` create tool once at the start of a new authoring task. Call the `resume` tool at the start of subsequent sessions — it is idempotent and will not create a duplicate. Call the `current` tool to inspect whether an open draft exists without forcing one into being.

**Deployment lock.** Creating or resuming a draft does not acquire the deployment lock; only deploy does. Multiple users may hold concurrent drafts. See `INGEST-VALIDATE-DEPLOY.md` for lock semantics.
