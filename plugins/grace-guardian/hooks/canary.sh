#!/bin/sh
# Grace Guardian — the canary.
#
# Every other hook of this plugin is an `mcp_tool` call. When the MCP connection to Grace is dead
# (OAuth token expired, server unreachable), Claude Code turns each of those into a NON-blocking
# error and says nothing to the user — who then believes the guardian is watching while it is not.
#
# This hook is the one thing that can still speak in that situation. It is plain `sh` + `curl`,
# it needs no token, and it only ever adds context. It never blocks anything.
#
# How it knows: `grace_guard_session` (the mcp_tool hook that runs alongside this one) cannot leave
# a mark on disk — it runs on Grace's servers. So the canary reads two independent signals:
#   1. Is Grace reachable at all?  → GET /mcp/v1/guard/ping (no auth).
#   2. Has the MCP connection been authenticated recently? → the presence of Grace's OAuth token
#      in Claude Code's own MCP credential store is not readable here, so we fall back to what the
#      user can act on: if Grace is reachable, remind them how to check the connection.
# Exit 0 always. Output is JSON `additionalContext` (SessionStart accepts it).

API="${GRACE_API_URL:-https://api.agent-grace.com}"

say() {
  # JSON-escape the minimal set of characters we use.
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
}

if ! command -v curl >/dev/null 2>&1; then
  say "Grace guardian: curl is not installed, so the guardian cannot check that Grace is reachable. If the guardian stays silent this session, run /mcp and reconnect grace."
  exit 0
fi

if curl -fsS --max-time 2 "$API/mcp/v1/guard/ping" >/dev/null 2>&1; then
  say "Grace guardian: Grace is reachable. If you see no message from Grace before your first edit this session, the MCP connection has probably expired — run /mcp and reconnect grace, otherwise the guardian is silently off."
else
  say "Grace guardian: Grace is NOT reachable right now ($API). The guardian is off for this session — nothing is being checked. Proceed with your own judgement and review changes before committing."
fi
exit 0
