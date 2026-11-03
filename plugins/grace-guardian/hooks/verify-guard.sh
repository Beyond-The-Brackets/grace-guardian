#!/bin/sh
# Grace Guardian — le verdict de fin de session (Stop).
#
# Compare ce que la session a FAIT (balises d'écriture posées par `require-guard.sh`, hors MCP) à
# ce que le Gardien a RÉPONDU (compteur posé par le serveur, à chaque outil de garde). Si des
# écritures ont eu lieu et que le Gardien n'a jamais répondu, c'est la panne silencieuse : du code
# a été modifié sans qu'aucun contrôle n'aboutisse. On le DIT, en clair, plutôt que de laisser
# l'absence de message passer pour une approbation.
#
# Ne bloque pas : à la fin d'un tour, bloquer n'annule pas les écritures déjà faites. La valeur est
# dans le fait de nommer l'état — c'est précisément ce qui manquait.
API="${GRACE_API_URL:-https://api.agent-grace.com}"

# L'id de session ne part JAMAIS tel quel : seulement ce condensat à sens unique, que le serveur
# recalcule de son côté (`hookSessionKey`, control-plane/src/mcp/guard/session-key.ts). Revue de
# l'annuaire Anthropic (2026-10-30) : un identifiant du poste ne doit pas être transmis à un tiers.
session_key() {
  [ -z "$1" ] && return 0
  if command -v shasum >/dev/null 2>&1; then
    printf 'grace-guardian:%s' "$1" | shasum -a 256 | cut -c1-32
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'grace-guardian:%s' "$1" | sha256sum | cut -c1-32
  fi
}
SESSION_KEY=$(session_key "${CLAUDE_SESSION_ID:-}")

# $1 = context for the model, $2 = the line the USER sees in the conversation (`systemMessage`).
say() {
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  shown=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' "$shown" "$msg"
  exit 0
}

[ -z "$SESSION_KEY" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

# Même empreinte que `require-guard.sh` et le serveur (`cwdHash`) : sha1 du dossier, 24 hexa. Elle
# permet au serveur de dire si le CONNECTEUR répond pendant que les hooks du plugin se taisent.
cwd_hash() {
  norm=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | tr '\\' '/' | sed 's#/*$##')
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$norm" | sha1sum | cut -c1-24
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$norm" | shasum -a 1 | cut -c1-24
  fi
}
CWD_HASH=$(cwd_hash)

BODY=$(curl -fsS --max-time 3 "$API/mcp/v1/guard/seen/$SESSION_KEY?cwd=$CWD_HASH" 2>/dev/null) || exit 0

# Pas de jq garanti : lecture par motif, sur des entiers que le serveur produit lui-même.
WRITES=$(printf '%s' "$BODY" | sed -n 's/.*"writes":\([0-9]*\).*/\1/p')
ANSWERED=$(printf '%s' "$BODY" | sed -n 's/.*"answered":\([0-9]*\).*/\1/p')
[ -z "$WRITES" ] && exit 0
[ "$WRITES" -eq 0 ] 2>/dev/null && exit 0

if [ "${ANSWERED:-0}" -eq 0 ] 2>/dev/null; then
  if printf '%s' "$BODY" | grep -q '"connectorActive":true'; then
    say "Grace guardian: HOOKS INACTIVE. $WRITES write(s) this session and no hook ever reached Grace — yet Grace's connector (the claude.ai one) is answering. A connector gives you Grace's tools but does NOT run hooks: only the plugin's own connection does. Run /mcp, find plugin:grace-guardian:grace and reconnect it, then review these changes before committing." "🧠 Grace — $WRITES write(s) this session, no hook reached Grace (the connector answers, the plugin does not). Run /mcp and reconnect plugin:grace-guardian:grace."
  fi
  say "Grace guardian: $WRITES write(s) this session and the guardian NEVER answered — nothing was checked. This is the silent failure mode: the MCP hooks fail non-blocking and say nothing. Run /mcp, reconnect plugin:grace-guardian:grace (the plugin's own connection), then review these changes before committing." "🧠 Grace — $WRITES write(s) this session and the guardian never answered: nothing was checked. Run /mcp and reconnect plugin:grace-guardian:grace."
fi
exit 0
