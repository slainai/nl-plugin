# AUTH — Concepts and Operational Notes

> **What this page is.** Authentication for live-tenant work is handled by the
> Flow Service API and the `mcp-remote` OAuth bridge this plugin uses — not by
> any CLI. This page records the protocol-level and operational details an agent
> needs: the JWT bearer model, OAuth 2.1 discovery, per-route scopes, token
> rotation, multi-tenancy, and the error envelope. Local config authoring with
> `openrecon` needs no authentication at all.

---

## Two layers: authentication, then scope

Every request to the platform passes two gates:

1. **Authentication** — a global NextAuth JWT middleware runs on every request.
   - Clients present a NextAuth session token as a bearer credential:
     `Authorization: Bearer <JWE NextAuth session token>`.
   - The token is a JWE the middleware decrypts using `NEXTAUTH_SECRET`.
   - On success it populates `request.state.user` with
     `{username, org_id, scopes}`.
   - It returns `401` on a missing, invalid, expired, or revoked token.

2. **Authorization (scope)** — individual routes declare
   `require_scope("<resource>:<verb>")` (e.g. `require_scope("recon-run:get")`).
   - The model is **default-deny**: an authenticated caller still needs the
     matching scope.
   - A caller whose `scopes` lack the required value receives `403` with an
     `insufficient_scope` error.

Through MCP, both gates apply unchanged — a tool call is replayed as a normal
in-process request (see `MCP.md`). An MCP tool can do nothing the caller's
token could not already do over plain HTTP.

---

## OAuth 2.1 discovery (how the token is obtained)

For MCP clients that obtain credentials via OAuth 2.1, the server publishes two
**unauthenticated** discovery endpoints. The `mcp-remote` bridge in this
plugin's `.mcp.json` uses them automatically on first connect.

- **`/.well-known/oauth-authorization-server`** (RFC 8414) — issuer plus the
  `authorize` / `token` / `userinfo` / `register` endpoints, supported grants
  (`authorization_code`, `refresh_token`), and PKCE method (`S256`).
- **`/.well-known/oauth-protected-resource`** (RFC 9728) — identifies `/mcp` as
  the protected resource and names the authorization server protecting it.

Both read the issuer from the server's `OAUTH_ISSUER_URL`. On first connect the
bridge opens a browser, the user signs in to their org, and the resulting token
is cached by `mcp-remote`. **No token is stored in this repository.**

> **Sandboxed agents.** The OAuth browser flow needs interactive sign-in and
> network egress to the deployment. In a recycled, network-restricted sandbox
> the flow cannot complete — connect from an environment that can reach the
> deployment and open a browser once; `mcp-remote` caches the credential for
> subsequent calls.

---

## Public / auth-excluded paths

A small set of paths bypass the JWT requirement so health checks, docs, and the
auth flows themselves stay reachable:

- `/health`, `/api/health`
- `/docs`, `/redoc`, `/openapi.json`
- public `/auth/*` and `/oauth/*` routes
- `/.well-known/oauth-authorization-server`
- `/api/events/publish` (secured separately by the worker callback token)

Everything else — including `/mcp` — requires a valid bearer token.

---

## Multi-tenancy: you are already scoped to one org

The platform is multi-tenant. Every authenticated request carries an `org_id`
on `request.state.user`, and **every business resource is scoped to that org**.
A caller only ever sees and acts on data belonging to their own organization.

This plugin assumes the customer's org **already exists** and the signed-in user
already belongs to it. There is no org-creation, org-user-management, or
support-access workflow here — those are internal platform-operator concerns,
not customer ones. If you need an org provisioned or a teammate added, that is
handled out of band by your numberlabs contact, not through these tools.

---

## Token rotation and expiry

NextAuth session tokens expire; `mcp-remote` holds a refresh token and renews
the access token transparently using the `refresh_token` grant advertised by
the discovery endpoint. If the refresh token itself is expired or revoked, calls
start returning `401` — re-connect the MCP server (re-run the OAuth flow) to
re-authenticate. A persistent `401` after a fresh sign-in is an identity/account
problem (the account is disabled or not yet provisioned), not a token problem.

A persistent `403 insufficient_scope`, by contrast, means the account is
authenticated but lacks the scope the route requires. Re-authenticating will not
fix it — the account's granted scopes must be widened by your numberlabs
contact.

---

## Worker callback token (informational)

`POST /api/events/publish` is excluded from the NextAuth middleware because it
is called by the Temporal worker, not an end user. It is authenticated by a
separate worker callback token (presented as a bearer, verified by SHA-256
lookup, bound to a specific `entity_id`). Customers do not call this endpoint;
it is documented only so the excluded-path list above makes sense.

---

## Error envelope

Errors come back with a consistent JSON envelope (surfaced through the MCP tool
result just as over HTTP):

```json
{
  "error": "string",
  "message": "string",
  "code": "string",
  "timestamp": "string",
  "details": {},
  "correlation_id": "string"
}
```

`details` and `correlation_id` are optional. Common status mappings:

- `ValidationError` → `400`
- Not-found errors → their mapped status (often `404`)
- `insufficient_scope` → `403`
- missing/invalid token → `401`
- Infrastructure errors → `503`
- Unhandled errors → `500`

When a tool call fails, read `message` and `code` first, then `correlation_id`
if you need to report the failure to platform support.

---

## Authoring needs no auth

`openrecon validate` / `ingest` / `run` are **fully local** — no token, no host,
no login. Always run `openrecon validate` before the first live tool call in any
session (see the `recon-authoring` and `numberlabs-configs` skills). The
authentication described on this page applies only to the live-tenant MCP tools.
