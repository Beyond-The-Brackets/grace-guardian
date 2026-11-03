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
# Périmètre : seuls les fichiers du DÉPÔT sont contrôlés. Le chemin vient du JSON reçu sur stdin
# (`tool_input.file_path`, ou `notebook_path`). Un fichier hors du dépôt — une note sous `~/.claude/`,
# un dossier voisin — passe sans balise ; un dossier qui n'est pas un dépôt git, tout passe. Sans
# cette condition, Grace injoignable refusait aussi un paragraphe de notes qui n'avait rien à voir.
#
# Résilience : le ping est tenté 2 fois (2,5 s) avec une courte pause, et un ping réussi dans les
# 120 dernières secondes de la session est réutilisé. Un ralentissement ponctuel ne refuse plus
# l'édition ; une vraie panne de plus de deux minutes, si.
#
# Échappatoire assumée : `GRACE_GUARD_FAIL_OPEN=1` laisse passer quand Grace est injoignable. Une
# porte sans échappatoire documentée finit contournée d'une façon qu'on ne contrôle pas — mieux
# vaut un interrupteur explicite, dont l'usage se voit.
API="${GRACE_API_URL:-https://api.agent-grace.com}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

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

deny() {
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg"
  exit 0
}

# --- 1. Ce fichier est-il dans le dépôt ? -----------------------------------------------------------
# Lecture par motif, sans jq (comme `verify-guard.sh`). Le premier `file_path` / `notebook_path` du
# JSON est celui de `tool_input`. Les séquences JSON `\\` et `\/` sont ramenées à `/`.
INPUT=$(cat 2>/dev/null | tr -d '\n\r' || true)
json_field() {
  # Première valeur de chaîne de la clé `$1` (le `sed` est glouton : il prendrait la dernière).
  printf '%s' "$INPUT" | awk -v key="\"$1\"" '{
    i = index($0, key); if (!i) exit
    r = substr($0, i + length(key))
    if (!sub(/^[ \t]*:[ \t]*"/, "", r)) exit
    if (match(r, /^([^"\\]|\\.)*/)) print substr(r, 1, RLENGTH)
  }'
}
FILE=$(json_field file_path)
[ -z "$FILE" ] && FILE=$(json_field notebook_path)
FILE=$(printf '%s' "$FILE" | sed 's#\\\\#/#g; s#\\/#/#g')

slashes() { printf '%s' "$1" | tr '\\' '/' | sed 's#//*#/#g; s#/$##'; }

if command -v git >/dev/null 2>&1; then
  ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null) || ROOT=""
  # Pas un dépôt git : rien à garder.
  [ -z "$ROOT" ] && exit 0
else
  ROOT=""
fi

if [ -n "$FILE" ] && [ -n "$ROOT" ]; then
  FILE=$(slashes "$FILE")
  ROOT_N=$(slashes "$ROOT")
  PROJ_N=$(slashes "$PROJECT_DIR")
  case "$FILE" in
    /*|[A-Za-z]:/*)
      # `rev-parse` résout les liens symboliques (macOS : /var → /private/var), pas l'éditeur :
      # on accepte les deux racines.
      case "$FILE" in
        "$ROOT_N"/*|"$PROJ_N"/*) ;;
        *) exit 0 ;;
      esac
      ;;
    ../*) exit 0 ;;
  esac
fi
# Chemin illisible : on garde le comportement fail-closed, c'est le cas sûr.

# Ce hook ne rend JAMAIS `allow` : ça approuverait l'écriture en court-circuitant la demande de
# permission normale de Claude Code (politique de l'annuaire Anthropic). Quand il laisse passer, il
# ne décide rien — il refuse (`deny`) ou se tait, et le flux de permission habituel tranche.
#
# Sans curl on ne peut RIEN affirmer. On ne bloque pas — bloquer tout travail parce qu'un utilitaire
# manque serait disproportionné — mais on le dit à l'utilisateur.
if ! command -v curl >/dev/null 2>&1; then
  printf '{"systemMessage":"Grace guardian: curl is missing, so this edit could not be checked."}\n'
  exit 0
fi

# --- 2. Grace répond-elle ? -------------------------------------------------------------------------
CACHE=""
[ -n "$SESSION_KEY" ] && CACHE="${TMPDIR:-/tmp}/grace-guard-$SESSION_KEY"
NOW=$(date +%s 2>/dev/null || echo 0)

recent_ping() {
  [ -n "$CACHE" ] && [ -f "$CACHE" ] || return 1
  last=$(cat "$CACHE" 2>/dev/null)
  case "$last" in ''|*[!0-9]*) return 1 ;; esac
  [ "$NOW" -gt 0 ] && [ $((NOW - last)) -lt 120 ]
}

REASON=""
reachable=0
if recent_ping; then
  reachable=1
else
  for attempt in 1 2; do
    curl -fsS --max-time 2.5 "$API/mcp/v1/guard/ping" >/dev/null 2>&1
    code=$?
    if [ "$code" -eq 0 ]; then
      reachable=1
      [ -n "$CACHE" ] && [ "$NOW" -gt 0 ] && printf '%s' "$NOW" > "$CACHE" 2>/dev/null
      break
    fi
    case "$code" in
      28) REASON="timeout after 2.5 s" ;;
      7) REASON="connection refused" ;;
      6) REASON="DNS lookup failed" ;;
      *) REASON="curl error $code" ;;
    esac
    [ "$attempt" -eq 1 ] && sleep 0.5
  done
fi

if [ "$reachable" -ne 1 ]; then
  if [ "${GRACE_GUARD_FAIL_OPEN:-0}" = "1" ]; then
    printf '{"systemMessage":"Grace guardian is unreachable and GRACE_GUARD_FAIL_OPEN=1 is set: this edit was not checked."}\n'
    exit 0
  fi
  deny "Grace guardian is unreachable ($API: $REASON, 2 attempts), so this edit cannot be checked. Refusing rather than letting an unchecked write through — that silence is what let eleven commits ship unverified on 2026-09-05. Fix the connection (/mcp, reconnect grace), or set GRACE_GUARD_FAIL_OPEN=1 to proceed knowingly."
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

if [ -n "$SESSION_KEY" ]; then
  CWD_HASH=$(cwd_hash)
  curl -fsS --max-time 2 -X POST "$API/mcp/v1/guard/beacon" \
    -H 'Content-Type: application/json' \
    -d "{\"sessionId\":\"$SESSION_KEY\",\"cwdHash\":\"$CWD_HASH\"}" >/dev/null 2>&1 || true
fi
exit 0
