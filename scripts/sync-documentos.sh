#!/usr/bin/env bash
#
# sync-documentos.sh — download any Documentos (impressoes) PDFs not yet on disk.
#
# Lists every document in every accordion category on the "Documentos" page,
# compares against ../.documentos.idx (the IDs already downloaded), and fetches
# only the new ones into a folder (under the project root) named after the group.
# On an expired session it logs in automatically and retries.
#
# Usually run via ../scripts/sync-all.sh, but works standalone too.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
FILES="$ROOT/Arquivos"
mkdir -p "$FILES"; cd "$FILES"

# shellcheck disable=SC1091
[ -f "$ROOT/.env" ] && source "$ROOT/.env"
PHPSESSID="${PHPSESSID:-}"
: "${HOST:=https://brunievieira.superlogica.net}"

IDX="$ROOT/.documentos.idx"
touch "$IDX"

CK="PHPSESSID=$PHPSESSID"
UA="Mozilla/5.0"
API="$HOST/areadocondomino/atual/impressoes/index"
DL="$HOST/clients/areadocondomino/documentos/download?id="

get() { curl -s -A "$UA" -b "$CK" -H "X-Requested-With: XMLHttpRequest" "$@"; }

folder_for() {
  case "$1" in
    Convocação) echo "Edital de convocação" ;;
    CND)        echo "Certidão negativa de débitos" ;;
    RH)         echo "Recursos humanos" ;;
    *)          echo "$1" ;;
  esac
}

sanitize() { printf '%s' "$1" | tr '/\\:*?"<>|' '-' | sed -E 's/[[:space:]]+/ /g; s/^ +| +$//g' | cut -c1-150; }

# --- auth check (auto-login + retry once if the session expired) -------------
authed() { [ "$(get "$API?itensPorPagina=1&pagina=1&doTipo=documento" | jq -r '.status // "ERR"' 2>/dev/null)" = "200" ]; }
if ! authed; then
  echo "Session expired — logging in…"
  "$SCRIPTS_DIR/login.sh" || exit $?          # propagate 2/3/4 to the caller
  source "$ROOT/.env"; CK="PHPSESSID=$PHPSESSID"
  authed || { echo "✗ Still unauthenticated after login." >&2; exit 3; }
fi

# --- discover categories dynamically from the accordion ---------------------
page=$(curl -s -A "$UA" -b "$CK" "$HOST/clients/areadocondomino/impressoes")
CATS=()
while IFS= read -r _c; do [ -n "$_c" ] && CATS+=("$_c"); done < <(printf '%s' "$page" \
  | perl -ne 'while(/listaDocumento="([^"]+)"/g){print "$1\n"}' \
  | awk '!seen[$0]++')

echo "Categories found: Documentos (avulsos)${CATS:+, }$(IFS=, ; echo "${CATS[*]}")"

new=0

download_group() {
  local url="$1" folder="$2" json rows
  json=$(get "$url")
  rows=$(printf '%s' "$json" | jq -c '.data[]? | {id: .id_impressao_fimp, titulo: .st_titulo_fimp}')
  [ -z "$rows" ] && return 0
  mkdir -p "$folder"
  while IFS= read -r row; do
    local id titulo base out
    id=$(printf '%s' "$row" | jq -r '.id')
    titulo=$(printf '%s' "$row" | jq -r '.titulo')
    grep -qxF "$id" "$IDX" && continue
    base=$(sanitize "$titulo"); [ -z "$base" ] && base="documento-$id"
    out="$folder/$base.pdf"
    [ -e "$out" ] && out="$folder/$base [$id].pdf"
    if curl -s -A "$UA" -b "$CK" -L "$DL$id" -o "$out" \
        && [ "$(head -c5 "$out")" = "%PDF-" ]; then
      echo "  + $folder/$(basename "$out")"
      echo "$id" >> "$IDX"
      new=$((new+1))
    else
      echo "  ! failed id=$id ($titulo)" >&2
      rm -f "$out"
    fi
  done <<< "$rows"
}

download_group "$API?itensPorPagina=300&pagina=1&doTipo=documento&apenasOutrosDocumentos=1" "Documentos"

for cat in "${CATS[@]}"; do
  enc=$(jq -rn --arg s "$cat" '$s|@uri')
  download_group "$API?itensPorPagina=300&pagina=1&doTipo=documento&categoria=$enc" "$(folder_for "$cat")"
done

if [ "$new" -eq 0 ]; then
  echo "✓ Documentos up to date ($(wc -l < "$IDX" | tr -d ' ') on disk)."
else
  echo "✓ Downloaded $new new document(s)."
fi
