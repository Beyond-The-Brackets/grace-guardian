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
SESSION_ID="${CLAUDE_SESSION_ID:-}"

say() {
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"%s"}}\n' "$msg"
  exit 0
}

[ -z "$SESSION_ID" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

BODY=$(curl -fsS --max-time 3 "$API/mcp/v1/guard/seen/$SESSION_ID" 2>/dev/null) || exit 0

# Pas de jq garanti : lecture par motif, sur des entiers que le serveur produit lui-même.
WRITES=$(printf '%s' "$BODY" | sed -n 's/.*"writes":\([0-9]*\).*/\1/p')
ANSWERED=$(printf '%s' "$BODY" | sed -n 's/.*"answered":\([0-9]*\).*/\1/p')
[ -z "$WRITES" ] && exit 0
[ "$WRITES" -eq 0 ] 2>/dev/null && exit 0

if [ "${ANSWERED:-0}" -eq 0 ] 2>/dev/null; then
  say "Grace guardian: $WRITES write(s) this session and the guardian NEVER answered — nothing was checked. This is the silent failure mode: the MCP hooks fail non-blocking and say nothing. Run /mcp and reconnect grace, then review these changes before committing."
fi
exit 0
