# MCP — The Flow Service API MCP Server

> **What this page is.** The numberlabs platform exposes its REST surface to
> agents through an MCP server mounted at `/mcp` on the Flow Service API. This
> plugin connects to it (see the bundled `.mcp.json`). This page is the durable
> reference for how that server behaves — the toolset map, per-request tool
> selection, how a tool call actually executes, and the auth it inherits.
> Exact tool names and request shapes come from the **advertised tool list**
> (`tools/list`) at runtime; this page covers what that list cannot express.

---

## What it is

The MCP server is a controlled **re-exposure of existing API routes** as MCP
tools — it adds no new capability. Every tool call is replayed through the full
FastAPI app, so nothing bypasses the platform's auth, scopes, rate limits, or
validation. A `403 insufficient_scope` over plain HTTP is a `403` through MCP
too.

- **Transport:** streamable HTTP, stateless sessions.
- **Endpoint:** a single exact route `/mcp` (not a path prefix — no
  `/mcp` → `/mcp/` redirect).
- **Tool surface:** 64 curated tools (down from the ~197 routes an unfiltered
  mount would expose).
- **Tool naming:** each tool's name is the wrapped route's OpenAPI
  `operationId`, so tool names line up 1:1 with the API reference. When a
  concept page below says "the tool that wraps `POST /api/...`", the actual
  tool name is that route's `operationId` — find it in the advertised list.

---

## How a tool call executes

Each MCP tool call is replayed as an **in-process HTTP request through the full
app**. The engine substitutes path parameters, splits query/header/body
parameters, forwards the caller's `Authorization` header, and issues the
request over an in-process ASGI transport.

Because the call re-enters the app as a normal request, it passes through the
entire middleware stack and the route's own scope check:

- CORS → NextAuth JWT authentication → rate limiting → body-size limit
- the route's `require_scope("<resource>:<verb>")` dependency
- request validation

This matters for the concept pages in this directory: behaviours that are
described there in terms of HTTP status codes (`409` on a concurrency
conflict, `404 no_materialized_view`, `422` on a bad `api_version`) surface
**through the tool result** exactly as they would over HTTP. The MCP layer is a
transport, not a new semantics layer.

---

## Toolsets

The 64 tools are partitioned into six named, pairwise-disjoint toolsets. This
plugin advertises all six (see `.mcp.json`), so both skills have what they need.

| Toolset | Tools | Covers | Skill that uses it |
|---|---|---|---|
| `authoring` | 15 | Ingest-config + match-config authoring, identifier types, journal templates (validate / deploy / publish / preview) | `numberlabs-configs` |
| `recon` | 15 | Recon-run lifecycle plus deep reads — matches, journals, balance, diff, queue, check-failures, unmatched-by | `numberlabs-runtime` |
| `actions` | 15 | Data-action execution and block-level debugging, sandbox actions, action lifecycle | `numberlabs-runtime` |
| `charts` | 5 | Chart query, materialization (+ status), create / update | `numberlabs-runtime` |
| `reports` | 6 | Report generation, preview, status, download, add / edit | `numberlabs-runtime` |
| `data` | 8 | Sources + freshness, refresh trigger / status / cancel, uploads | `numberlabs-runtime` |

---

## Per-request tool selection

A client narrows the advertised tool list per request with two headers. With
**neither** set, all 64 tools are listed.

- **`X-MCP-Toolsets`** — comma-separated toolset names (e.g. `authoring,recon`).
  The advertised tools are the union of those groups.
- **`X-MCP-Tools`** — comma-separated exact tool names (operationIds), added
  individually on top of any selected toolsets.

Unknown group names and unknown tool names are ignored silently.

> Tool selection is **discovery-only**. The headers narrow what `tools/list`
> advertises; they do not widen — or restrict — what a tool may *execute*.
> Execution is always gated by the curated 64-tool allowlist and by
> `require_scope` on the replayed call. Trimming the toolset keeps the agent's
> menu focused; it is not a security boundary.

**Focusing the menu for a task.** The bundled `.mcp.json` advertises all six
toolsets. If you want a leaner menu for a session — e.g. pure authoring — copy
`.mcp.json` into your project and trim the `X-MCP-Toolsets` header value, or set
`X-MCP-Tools` to a handful of operationIds. This only affects which tools the
agent sees, never what it can do.

---

## Authentication & OAuth discovery

`/mcp` is **not** an auth-excluded path — it is guarded by the same NextAuth
JWT middleware as every other app route. Clients present a bearer token, and
that token is forwarded into each replayed tool call. See `AUTH.md` for the
full JWT + scope model and how a customer obtains a token.

For MCP clients that discover and obtain credentials via OAuth 2.1, the server
publishes two **unauthenticated** discovery endpoints:

- **`/.well-known/oauth-authorization-server`** (RFC 8414) —
  authorization-server metadata: `issuer`, `authorize` / `token` / `userinfo`
  / `register` endpoints, supported grants (`authorization_code`,
  `refresh_token`), and PKCE method (`S256`).
- **`/.well-known/oauth-protected-resource`** (RFC 9728) — identifies `/mcp`
  as the protected resource and points at the authorization server.

Both read the issuer from the server's configured `OAUTH_ISSUER_URL`. The
`mcp-remote` bridge this plugin uses (see below) performs this OAuth flow for
you on first connect.

---

## How this plugin connects

The bundled `.mcp.json` bridges through `mcp-remote`, which speaks
OAuth/streamable-HTTP to the deployment and exposes the tools to Claude Code:

```json
{
  "mcpServers": {
    "numberlabs": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote",
        "https://api.numberlabs.io/mcp",
        "--header", "X-MCP-Toolsets:authoring,recon,actions,charts,reports,data"
      ]
    }
  }
}
```

- **First connect** opens an OAuth 2.1 browser flow against the discovery
  endpoints; `mcp-remote` caches the resulting token. No token is stored in
  this repo.
- **Pointing at another environment** (staging / local): change the URL to the
  matching `mcp_url` from `defaults.json`
  (`https://staging-api.numberlabs.io/mcp` or `http://localhost:3033/mcp`).
- **`npx` / `mcp-remote`** require Node.js on PATH. In a sandbox without
  network egress the OAuth flow and `npx` fetch will fail — connect from an
  environment that can reach the deployment.

---

## Why MCP here (and not a CLI)

The previous generation of this plugin shipped a `nlcloud` Rust CLI as the
live-server transport, because exposing ~130–197 raw REST routes as tools would
burn context. The platform now solves that problem itself: the `/mcp` mount is
**curated to 64 tools** and **further trimmable per request** via
`X-MCP-Toolsets`. So a customer gets a focused, auth-correct tool surface with
no CLI to install or log into — the only local binary is `openrecon`, used
purely for **offline** config authoring and validation (see the
`recon-authoring` skill).
