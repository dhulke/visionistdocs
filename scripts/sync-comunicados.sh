#!/usr/bin/env bash
#
# sync-comunicados.sh — download any Comunicados not yet on disk.
#
# Lists every comunicado, compares against ../.comunicados.idx, and for each new
# one writes a self-contained HTML file (title + date + body) plus every
# attachment (PDFs / images), rewriting the body so it renders offline.
# On an expired session it logs in automatically and retries.
#
# Usually run via ../scripts/sync-all.sh, but works standalone too.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
[ -f "$ROOT/.env" ] && source "$ROOT/.env"
PHPSESSID="${PHPSESSID:-}"
: "${HOST:=https://brunievieira.superlogica.net}"

OUT="$ROOT/Arquivos/Comunicados"
IDX="$ROOT/.comunicados.idx"
mkdir -p "$OUT"; touch "$IDX"

CK="PHPSESSID=$PHPSESSID"
UA="Mozilla/5.0"
API="$HOST/areadocondomino/atual/comunicados/index?itensPorPagina=1000&pagina=1&doTipo=documento"
REL="$HOST/clients/areadocondomino/publico/relatorios?chavePublica="

get() { curl -s -A "$UA" -b "$CK" -H "X-Requested-With: XMLHttpRequest" "$@"; }

sanitize() { printf '%s' "$1" | tr '/\\:*?"<>|' '-' | sed -E 's/[[:space:]]+/ /g; s/^ +| +$//g' | cut -c1-110; }
esc_html() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

sniff() {
  local hex; hex=$(head -c4 "$1" | od -An -tx1 | tr -d ' \n')
  case "$hex" in
    255044462d*|25504446*) echo pdf ;;
    ffd8ff*)               echo jpg ;;
    89504e47)              echo png ;;
    47494638)              echo gif ;;
    *)                     echo "" ;;
  esac
}

# --- fetch full list; auto-login + retry once if the session expired ---------
json=$(get "$API")
if [ "$(printf '%s' "$json" | jq -r '.status // "ERR"' 2>/dev/null)" != "200" ]; then
  echo "Session expired — logging in…"
  "$SCRIPTS_DIR/login.sh" || exit $?          # propagate 2/3/4 to the caller
  source "$ROOT/.env"; CK="PHPSESSID=$PHPSESSID"
  json=$(get "$API")
  if [ "$(printf '%s' "$json" | jq -r '.status // "ERR"' 2>/dev/null)" != "200" ]; then
    echo "✗ Still unauthenticated after login." >&2; exit 3
  fi
fi

total=$(printf '%s' "$json" | jq '.data | length')
echo "Server lists $total comunicados; $(wc -l < "$IDX" | tr -d ' ') already on disk."

new=0
while IFS= read -r row; do
  id=$(printf '%s'    "$row" | jq -r '.id')
  grep -qxF "$id" "$IDX" && continue

  titulo=$(printf '%s' "$row" | jq -r '.titulo')
  dt=$(printf '%s'     "$row" | jq -r '.dt')
  texto=$(printf '%s'  "$row" | jq -r '.texto')
  [ "$texto" = "null" ] || [ -z "$texto" ] && texto="<p>(sem texto)</p>"

  iso="${dt:6:4}-${dt:0:2}-${dt:3:2}"
  base="$iso - $(sanitize "$titulo") [$id]"

  n=0
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    n=$((n+1))
    tmp="$OUT/.tmp_$key"
    curl -s -A "$UA" -b "$CK" -L "$REL$key" -o "$tmp" || true
    ext=$(sniff "$tmp")
    if [ -z "$ext" ]; then rm -f "$tmp"; continue; fi
    att="$base - anexo $n.$ext"
    mv "$tmp" "$OUT/$att"
    texto=$(KEY="$key" ATT="$att" perl -pe 's{https?://[^"'"'"'>\s]*chavePublica=\Q$ENV{KEY}\E(?:&(?:amp;)?filename=[^"'"'"'>\s]*)?}{$ENV{ATT}}g' <<< "$texto")
  done < <(printf '%s' "$texto" | grep -oE 'chavePublica=[0-9a-f]+' | sed 's/chavePublica=//' | awk '!seen[$0]++')

  {
    printf '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>%s</title></head>\n' "$(esc_html "$titulo")"
    printf '<body style="max-width:800px;margin:2rem auto;font-family:system-ui,Arial,sans-serif;line-height:1.5;padding:0 1rem">\n'
    printf '<h1 style="font-size:1.3rem">%s</h1>\n' "$(esc_html "$titulo")"
    printf '<p style="color:#666"><em>Comunicado #%s — %s</em></p><hr>\n' "$id" "$(esc_html "$dt")"
    printf '%s\n</body></html>\n' "$texto"
  } > "$OUT/$base.html"

  echo "  + $base"
  echo "$id" >> "$IDX"
  new=$((new+1))
done < <(printf '%s' "$json" | jq -c '.data[]
          | {id: .id_comunicado_com, titulo: .st_titulo_com, dt: .dt_comunicado_com, texto: .st_texto_com}' \
        | jq -sc 'sort_by(.dt[6:10]+.dt[0:2]+.dt[3:5], (.id|tonumber)) | .[]')

if [ "$new" -eq 0 ]; then
  echo "✓ Comunicados up to date."
else
  echo "✓ Downloaded $new new comunicado(s)."
fi
