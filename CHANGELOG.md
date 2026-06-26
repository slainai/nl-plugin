# CHANGELOG


## v0.1.0 (2026-06-26)

### Continuous Integration

- Post changelog to Slack on published release ([#1](https://github.com/slainai/nl-plugin/pull/1),
  [`ea77120`](https://github.com/slainai/nl-plugin/commit/ea77120e38d2a21d6c562c9b55cab29d7e905f84))

Adds release-slack.yml: on `release: published`, formats the release body as Slack mrkdwn and POSTs
  it to an Incoming Webhook (secret SLACK_WEBHOOK_URL). No-ops with a warning if the secret is
  unset, so it never fails a release. Skips pre-releases.

Co-authored-by: Claude Opus 4.8 (1M context) <noreply@anthropic.com>

### Features

- Initial numberlabs plugin (openrecon CLI + Flow Service API MCP)
  ([`68ebd3b`](https://github.com/slainai/nl-plugin/commit/68ebd3b85ae93d7b4adde0d343ce180c28a7f44f))

Customer-facing Claude Code / OpenCode plugin: - recon-authoring skill: local config
  authoring/validation with the bundled openrecon binary (no Python). Unix binaries shipped
  xz-compressed under bin/; Windows shipped as the release .zip (zip is native on Windows, no xz
  needed). - numberlabs-configs / numberlabs-runtime skills: drive a live tenant via the Flow
  Service API MCP server (.mcp.json, mcp-remote + OAuth 2.1). - 8 api/ concept pages, spec grammars,
  annotated examples. - install-openrecon.sh expands the right archive per platform; bundles all 5
  targets (mac x2, linux x2, windows x64) so Cowork sessions can validate offline.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
