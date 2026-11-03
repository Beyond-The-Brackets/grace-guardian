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

# $1 = context for the model, $2 = the one line the USER sees in the conversation (`systemMessage`:
# shown to the human, never handed to the model, and neither an approval nor a rewrite of a call).
say() {
  # JSON-escape the minimal set of characters we use.
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  shown=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$shown" "$msg"
}

if ! command -v curl >/dev/null 2>&1; then
  say "Grace guardian: curl is not installed, so the guardian cannot check that Grace is reachable. If the guardian stays silent this session, run /mcp and reconnect grace." "🧠 Grace — cannot check that Grace is reachable (curl is missing)."
  exit 0
fi

if curl -fsS --max-time 2 "$API/mcp/v1/guard/ping" >/dev/null 2>&1; then
  # Reachable is not « on »: the hooks run through the plugin's own connection, which this script
  # cannot see. Saying « guardian on » here was a lie whenever that connection was not signed in —
  # the one proof is Grace's hello on the first prompt, so the line promises it instead.
  say "Grace guardian: the plugin is loaded and Grace is reachable. The hooks only work through the plugin's OWN connection, listed in /mcp as plugin:grace-guardian:grace — the claude.ai connector named grace gives you Grace's tools but does not run hooks. Grace greets the user on their first message; if no message from Grace appears, that connection has expired or is not connected: run /mcp and reconnect it, otherwise the guardian is silently off." "🧠 Grace — reachable. I'll say hello on your first message; if I don't, open /mcp and connect plugin:grace-guardian:grace."
else
  say "Grace guardian: Grace is NOT reachable right now ($API). The guardian is off for this session — nothing is being checked. Proceed with your own judgement and review changes before committing." "🧠 Grace — NOT reachable: nothing is being checked this session."
fi
exit 0
