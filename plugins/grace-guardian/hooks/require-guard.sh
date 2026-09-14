#!/bin/sh
# Grace Guardian — la porte qui échoue FERMÉE (PreToolUse sur Edit/Write/MultiEdit).
#
# Pourquoi ce hook existe. Tous les autres hooks de ce plugin sont des `mcp_tool`. Quand la
# connexion MCP est morte, Claude Code en fait une erreur NON BLOQUANTE et n'en dit rien : l'agent
# écrit, l'utilisateur croit que le Gardien surveille, et rien n'est vérifié. Le 2026-09-05, sur un
# compte en mode `strict`, onze commits sont passés sans qu'un seul contrôle aboutisse — et ni
# l'utilisateur ni l'agent n'avaient de quoi s'en apercevoir.
#
# Ce hook est en `sh` + `curl`, il ne dépend d'AUCUN jeton, et il peut REFUSER. Deux choses :
#   1. Grace injoignable  → `permissionDecision: deny`. « Pas vérifié » ne doit plus ressembler à
#      « rien à signaler ». C'est le sens de « fail closed ».
#   2. Grace joignable    → on pose une BALISE d'écriture par un chemin indépendant du MCP, pour
#      que la fin de session puisse comparer « écritures tentées » et « réponses du Gardien ».
#
# Échappatoire assumée : `GRACE_GUARD_FAIL_OPEN=1` laisse passer quand Grace est injoignable. Une
# porte sans échappatoire documentée finit contournée d'une façon qu'on ne contrôle pas — mieux
# vaut un interrupteur explicite, dont l'usage se voit.
API="${GRACE_API_URL:-https://api.agent-grace.com}"
SESSION_ID="${CLAUDE_SESSION_ID:-}"

deny() {
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg"
  exit 0
}

# Sans curl on ne peut RIEN affirmer. On laisse passer, mais en le disant : bloquer tout travail
# parce qu'un utilitaire manque serait disproportionné.
if ! command -v curl >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Grace guardian: curl missing, cannot verify — NOT CHECKED."}}\n'
  exit 0
fi

if ! curl -fsS --max-time 3 "$API/mcp/v1/guard/ping" >/dev/null 2>&1; then
  if [ "${GRACE_GUARD_FAIL_OPEN:-0}" = "1" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Grace guardian is UNREACHABLE and GRACE_GUARD_FAIL_OPEN=1 — this edit was NOT checked."}}\n'
    exit 0
  fi
  deny "Grace guardian is unreachable ($API), so this edit cannot be checked. Refusing rather than letting an unchecked write through — that silence is what let eleven commits ship unverified on 2026-09-05. Fix the connection (/mcp, reconnect grace), or set GRACE_GUARD_FAIL_OPEN=1 to proceed knowingly."
fi

# Joignable : on enregistre l'intention d'écrire, hors MCP. Best-effort — la balise ne doit jamais
# empêcher un travail légitime, elle sert seulement à rendre la panne visible à la fin.
#
# On envoie une EMPREINTE du dossier, jamais le chemin : elle suffit au serveur pour rattacher la
# session au compte (index inverse posé à la liaison) et faire apparaître la session sur /editor.
# Même calcul que `cwdHash()` côté serveur — sha1 du chemin normalisé, tronqué à 24 hexa. Une
# divergence ne casse rien : le rattachement échoue, la balise reste lisible par `seen/:id`.
cwd_hash() {
  norm=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | tr '\\' '/' | sed 's#/*$##')
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$norm" | sha1sum | cut -c1-24
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$norm" | shasum -a 1 | cut -c1-24
  fi
}

if [ -n "$SESSION_ID" ]; then
  CWD_HASH=$(cwd_hash)
  curl -fsS --max-time 2 -X POST "$API/mcp/v1/guard/beacon" \
    -H 'Content-Type: application/json' \
    -d "{\"sessionId\":\"$SESSION_ID\",\"cwdHash\":\"$CWD_HASH\"}" >/dev/null 2>&1 || true
fi
exit 0
