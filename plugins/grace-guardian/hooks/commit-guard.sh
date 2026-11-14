#!/bin/sh
# Grace Guardian — dit au serveur QUELS FICHIERS un `git commit` / `git push` va envoyer, et
# l'EMPREINTE de ce que git va réellement committer.
#
# Pourquoi la liste. `grace_guard_command` ne reçoit que le texte de la commande et le dossier : il
# ne sait pas ce que git va mettre dans le commit. Il retenait donc un commit propre à cause d'un
# fichier de la session qui n'y figurait pas (constaté chez un client : l'agent n'a pas pu committer
# ni pousser un changement relu, il a fallu le faire à la main). Ce hook lit l'index avec git et
# envoie la liste ; le serveur ne répond que sur ces fichiers.
#
# Pourquoi les empreintes (PASS.01, plugin 0.8.0). La porte s'ouvrait sur la DÉCLARATION qu'une
# revue avait eu lieu (`grace_review_submit`), sans rien savoir des octets relus ni de ceux qui
# partent. Ce hook calcule, avec git et sans l'agent, le sha256 de chaque fichier tel qu'il sera
# committé ; le serveur le compare à l'empreinte de la version relue, et retient le fichier si elles
# diffèrent. Aucun contenu ne part : seulement des chemins et des empreintes.
#
# - `git commit`            → l'index (`git diff --cached`) : empreinte du blob indexé, tel que
#                             l'éditeur le voit (`cat-file --filters` : fins de ligne, LFS…)
# - `git commit -a / --all` → l'arbre de travail (`git diff HEAD`)
# - index vide              → `git add … && git commit` : rien n'est encore indexé. Pas de liste
#                             (le serveur garde toute la session), mais les empreintes de l'arbre de
#                             travail, puisque c'est lui que `git add` va indexer
# - `git push`              → fichiers de `@{u}..HEAD` (repli `origin/HEAD..HEAD`), sans empreinte
# - toute autre commande    → rien du tout.
#
# Les chemins partent RELATIFS AU DOSSIER DE LA SESSION (le `cwd` du hook), comme les clés que le
# serveur tient : un dépôt ouvert dans un sous-dossier ne fait plus correspondre des chemins relatifs
# à deux racines différentes.
#
# Strictement best-effort et SILENCIEUX : il ne bloque jamais, n'imprime rien. Sans liste, le serveur
# retombe sur l'ensemble de la session — le comportement d'avant, jamais un feu vert.
#
# Il tourne EN PARALLÈLE de `grace_guard_command` (Claude Code lance les hooks d'un matcher
# ensemble) : le serveur attend donc brièvement la liste.
API="${GRACE_API_URL:-https://api.agent-grace.com}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
MAX_FILES=200

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

# sha256 hexadécimal de stdin — le même calcul que `shasum -a 256 <fichier>` côté agent.
sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-64
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -c1-64
  fi
}

[ -z "$SESSION_KEY" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null | tr -d '\n\r' || true)
json_field() {
  # Première valeur de chaîne de la clé `$1` (le `sed` est glouton : il prendrait la dernière clé).
  # `cwd` précède `tool_input` dans l'entrée des hooks : sa première occurrence est la bonne.
  printf '%s' "$INPUT" | awk -v key="\"$1\"" '{
    i = index($0, key); if (!i) exit
    r = substr($0, i + length(key))
    if (!sub(/^[ \t]*:[ \t]*"/, "", r)) exit
    if (match(r, /^([^"\\]|\\.)*/)) print substr(r, 1, RLENGTH)
  }'
}
CMD=$(json_field command)
[ -z "$CMD" ] && exit 0

# Les options de git qui prennent un ARGUMENT (`-C dir`, `-c k=v`) doivent pouvoir précéder la sous-commande.
GIT='(^|[;&|(]|[[:space:]])git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*'
COMMITS=0
PUSHES=0
printf '%s' "$CMD" | grep -Eq "${GIT}commit" && COMMITS=1
printf '%s' "$CMD" | grep -Eq "${GIT}push" && PUSHES=1
[ "$COMMITS" -eq 0 ] && [ "$PUSHES" -eq 0 ] && exit 0

# Le dossier de la session, celui contre lequel le serveur situe les chemins.
CWD=$(json_field cwd | sed 's#\\\\#/#g; s#\\/#/#g')
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PROJECT_DIR"
TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$TOP" ] || exit 0
# Le dossier de la session vu depuis la racine du dépôt (`control-plane/`, ou vide à la racine).
PREFIX=$(git -C "$CWD" rev-parse --show-prefix 2>/dev/null) || PREFIX=""

TMPF=$(mktemp 2>/dev/null) || TMPF=""
cleanup() { [ -n "$TMPF" ] && rm -f "$TMPF"; }
trap cleanup EXIT

# Un chemin relatif à la racine → relatif au dossier de la session. Hors de ce dossier : `../…`,
# que le serveur ne rattache à rien (il ne tient que des chemins sous le dossier de la session).
rel_to_cwd() {
  case "$1" in
    "$PREFIX"*) printf '%s' "${1#"$PREFIX"}" ;;
    *) printf '../%s' "$1" ;;
  esac
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

json_array() {
  # Une ligne par chemin (relatif à la racine) sur stdin → tableau JSON de chemins relatifs au dossier.
  first=1
  printf '['
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '"%s"' "$(json_escape "$(rel_to_cwd "$p")")"
  done
  printf ']'
}

# L'empreinte de `$1` (relatif à la racine) telle que git va la committer depuis l'index : le blob
# indexé passé par les filtres (ce que l'éditeur voit sur le disque), ou `deleted`. Rien si git ne
# sait pas répondre — mieux vaut pas d'empreinte (la règle d'avant s'applique) qu'une fausse.
index_sha() {
  if ! git -C "$TOP" cat-file -e ":$1" 2>/dev/null; then
    printf 'deleted'
    return 0
  fi
  [ -n "$TMPF" ] || return 0
  git -C "$TOP" cat-file --filters ":$1" >"$TMPF" 2>/dev/null || return 0
  sha256_stdin <"$TMPF"
}

# L'empreinte de `$1` dans l'arbre de travail : ce que `git add` / `commit -a` vont indexer.
worktree_sha() {
  if [ -f "$TOP/$1" ]; then
    sha256_stdin <"$TOP/$1"
  elif [ ! -e "$TOP/$1" ]; then
    printf 'deleted'
  fi
}

# `$1` = index | worktree ; une ligne par chemin sur stdin → objet JSON { chemin: empreinte }.
json_hashes() {
  first=1
  n=0
  printf '{'
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in "$PREFIX"*) ;; *) continue ;; esac
    [ "$n" -ge "$MAX_FILES" ] && break
    if [ "$1" = "index" ]; then sha=$(index_sha "$p"); else sha=$(worktree_sha "$p"); fi
    [ -z "$sha" ] && continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    n=$((n + 1))
    printf '"%s":"%s"' "$(json_escape "$(rel_to_cwd "$p")")" "$sha"
  done
  printf '}'
}

COMMIT_JSON=""
PUSH_JSON=""
HASH_JSON=""
if [ "$COMMITS" -eq 1 ]; then
  if printf '%s' "$CMD" | grep -Eq "${GIT}commit[[:space:]]+(.*[[:space:]])?(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|\$)"; then
    LIST=$(git -C "$TOP" -c core.quotepath=off diff --name-only HEAD 2>/dev/null)
    SOURCE=worktree
  else
    LIST=$(git -C "$TOP" -c core.quotepath=off diff --cached --name-only 2>/dev/null)
    SOURCE=index
  fi
  if [ -n "$LIST" ]; then
    COMMIT_JSON=$(printf '%s\n' "$LIST" | json_array)
    HASH_JSON=$(printf '%s\n' "$LIST" | head -n "$MAX_FILES" | json_hashes "$SOURCE")
  else
    # Index vide (`git add … && git commit`, ou un commit avec chemins : rien n'est encore indexé
    # quand ce hook tourne) : pas de liste — une liste vide serait lue « aucun fichier ne part ».
    # Mais l'arbre de travail est ce que `git add` va indexer : ses empreintes valent pour ce commit.
    WORK=$( {
      git -C "$TOP" -c core.quotepath=off diff --name-only HEAD 2>/dev/null
      git -C "$TOP" -c core.quotepath=off ls-files --others --exclude-standard 2>/dev/null
    } | head -n "$MAX_FILES")
    [ -n "$WORK" ] && HASH_JSON=$(printf '%s\n' "$WORK" | json_hashes worktree)
  fi
  [ "$HASH_JSON" = "{}" ] && HASH_JSON=""
fi
# `commit && push` : ce que le push enverra n'existe pas encore, on ne devine pas.
if [ "$PUSHES" -eq 1 ] && [ "$COMMITS" -eq 0 ]; then
  LIST=$(git -C "$TOP" -c core.quotepath=off diff --name-only '@{u}..HEAD' 2>/dev/null) \
    || LIST=$(git -C "$TOP" -c core.quotepath=off diff --name-only 'origin/HEAD..HEAD' 2>/dev/null) || LIST=""
  [ -n "$LIST" ] && PUSH_JSON=$(printf '%s\n' "$LIST" | json_array)
fi

BODY="{\"sessionId\":\"$SESSION_KEY\""
[ -n "$COMMIT_JSON" ] && BODY="$BODY,\"commit\":$COMMIT_JSON"
[ -n "$PUSH_JSON" ] && BODY="$BODY,\"push\":$PUSH_JSON"
[ -n "$HASH_JSON" ] && BODY="$BODY,\"hashes\":$HASH_JSON"
BODY="$BODY}"

if [ -n "${GRACE_COMMIT_GUARD_DRY_RUN:-}" ]; then
  # Pour les tests du plugin : le corps qui partirait, sans réseau.
  printf '%s\n' "$BODY"
  exit 0
fi

curl -fsS --max-time 2 -X POST "$API/mcp/v1/guard/sent" \
  -H 'Content-Type: application/json' -d "$BODY" >/dev/null 2>&1 || true
exit 0
