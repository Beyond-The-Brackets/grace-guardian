#!/bin/sh
# Grace Guardian — dit au serveur QUELS FICHIERS un `git commit` / `git push` va envoyer.
#
# Pourquoi. `grace_guard_command` ne reçoit que le texte de la commande et le dossier : il ne sait
# pas ce que git va mettre dans le commit. Il retenait donc un commit propre à cause d'un fichier de
# la session qui n'y figurait pas (constaté chez un client : l'agent n'a pas pu committer ni pousser
# un changement relu, il a fallu le faire à la main). Ce hook lit l'index avec git et envoie la
# liste, en chemins RELATIFS ; le serveur ne répond que sur ces fichiers.
#
# - `git commit`      → `git diff --cached --name-only` (avec `-a` / `--all` : `git diff --name-only HEAD`)
# - `git push`        → fichiers de `@{u}..HEAD` (repli `origin/HEAD..HEAD`)
# - toute autre commande → rien du tout.
#
# Strictement best-effort et SILENCIEUX : il ne bloque jamais, n'imprime rien. Sans liste, le serveur
# retombe sur l'ensemble de la session — le comportement d'avant, jamais un feu vert.
#
# Il tourne EN PARALLÈLE de `grace_guard_command` (Claude Code lance les hooks d'un matcher
# ensemble) : le serveur attend donc brièvement la liste.
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

[ -z "$SESSION_KEY" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null | tr -d '\n\r' || true)
# Première valeur de chaîne de `command` (le `sed` est glouton : il prendrait la dernière clé).
CMD=$(printf '%s' "$INPUT" | awk '{
  i = index($0, "\"command\""); if (!i) exit
  r = substr($0, i + 9)
  if (!sub(/^[ \t]*:[ \t]*"/, "", r)) exit
  if (match(r, /^([^"\\]|\\.)*/)) print substr(r, 1, RLENGTH)
}')
[ -z "$CMD" ] && exit 0

# Les options de git qui prennent un ARGUMENT (`-C dir`, `-c k=v`) doivent pouvoir précéder la sous-commande.
GIT='(^|[;&|(]|[[:space:]])git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*'
COMMITS=0
PUSHES=0
printf '%s' "$CMD" | grep -Eq "${GIT}commit" && COMMITS=1
printf '%s' "$CMD" | grep -Eq "${GIT}push" && PUSHES=1
[ "$COMMITS" -eq 0 ] && [ "$PUSHES" -eq 0 ] && exit 0

git -C "$PROJECT_DIR" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

json_array() {
  # Une ligne par chemin sur stdin → tableau JSON de chaînes (\ et " échappés).
  first=1
  printf '['
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    esc=$(printf '%s' "$p" | sed 's/\\/\\\\/g; s/"/\\"/g')
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '"%s"' "$esc"
  done
  printf ']'
}

COMMIT_JSON=""
PUSH_JSON=""
if [ "$COMMITS" -eq 1 ]; then
  if printf '%s' "$CMD" | grep -Eq "${GIT}commit[[:space:]]+(.*[[:space:]])?(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|\$)"; then
    LIST=$(git -C "$PROJECT_DIR" -c core.quotepath=off diff --name-only HEAD 2>/dev/null)
  else
    LIST=$(git -C "$PROJECT_DIR" -c core.quotepath=off diff --cached --name-only 2>/dev/null)
  fi
  # Index vide (`git add … && git commit`, ou un commit avec chemins : rien n'est encore indexé quand
  # ce hook tourne) : on n'envoie RIEN. Une liste vide serait lue « aucun fichier ne part ».
  [ -n "$LIST" ] && COMMIT_JSON=$(printf '%s\n' "$LIST" | json_array)
fi
# `commit && push` : ce que le push enverra n'existe pas encore, on ne devine pas.
if [ "$PUSHES" -eq 1 ] && [ "$COMMITS" -eq 0 ]; then
  LIST=$(git -C "$PROJECT_DIR" -c core.quotepath=off diff --name-only '@{u}..HEAD' 2>/dev/null) \
    || LIST=$(git -C "$PROJECT_DIR" -c core.quotepath=off diff --name-only 'origin/HEAD..HEAD' 2>/dev/null) || LIST=""
  [ -n "$LIST" ] && PUSH_JSON=$(printf '%s\n' "$LIST" | json_array)
fi

BODY="{\"sessionId\":\"$SESSION_KEY\""
[ -n "$COMMIT_JSON" ] && BODY="$BODY,\"commit\":$COMMIT_JSON"
[ -n "$PUSH_JSON" ] && BODY="$BODY,\"push\":$PUSH_JSON"
BODY="$BODY}"

curl -fsS --max-time 2 -X POST "$API/mcp/v1/guard/sent" \
  -H 'Content-Type: application/json' -d "$BODY" >/dev/null 2>&1 || true
exit 0
