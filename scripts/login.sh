#!/usr/bin/env bash
#
# login.sh — authenticate to the área do condômino and store a fresh session.
#
# Reads VISIONIST_EMAIL / VISIONIST_SENHA from ../.env, logs in, and writes the
# returned session token back into ../.env as PHPSESSID. The sync scripts call
# this automatically when their session has expired.
#
# Exit codes: 0 ok · 2 invalid credentials · 3 could-not-authenticate · 4 no credentials

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
ENV="$ROOT/.env"

EX_BADCREDS=2; EX_AUTHFAIL=3; EX_NOCREDS=4

# shellcheck disable=SC1090
[ -f "$ENV" ] && source "$ENV"
HOST="${HOST:-https://brunievieira.superlogica.net}"

if [ -z "${VISIONIST_EMAIL:-}" ] || [ -z "${VISIONIST_SENHA:-}" ]; then
  echo "✗ No credentials found in $ENV (VISIONIST_EMAIL / VISIONIST_SENHA)." >&2
  exit $EX_NOCREDS
fi

attempt_login() {
  curl -s -A "Mozilla/5.0" -H "X-Requested-With: XMLHttpRequest" \
    --data-urlencode "email=$VISIONIST_EMAIL" \
    --data-urlencode "senha=$VISIONIST_SENHA" \
    --data-urlencode "FL_LOGIN_WEB=1" \
    --data-urlencode "url=" --data-urlencode "CHAVE=" \
    --data-urlencode "idCondominio=" --data-urlencode "hashemail=" \
    "$HOST/areadocondomino/atual/publico/auth"
}

# The backend returns 200/202 + a session token on success. Wrong credentials
# come back as 401 with a message mentioning "senha"; transient failures (e.g.
# "Redis server went away") are also 401 but retryable — so we retry those and
# fail fast on real credential errors.
status=ERR; session=""; msg=""
for attempt in 1 2 3 4; do
  resp=$(attempt_login || true)
  status=$(printf '%s' "$resp" | jq -r '.status // "ERR"' 2>/dev/null || echo ERR)
  session=$(printf '%s' "$resp" | jq -r '.session // .data.session // empty' 2>/dev/null || true)
  msg=$(printf '%s' "$resp" | jq -r '.msg // empty' 2>/dev/null || true)

  { [ "$status" = "200" ] || [ "$status" = "202" ]; } && [ -n "$session" ] && break

  case "$msg" in
    *senha*|*Senha*|*SENHA*)
      echo "✗ Invalid credentials: $msg" >&2
      exit $EX_BADCREDS ;;
  esac
  [ "$attempt" -lt 4 ] && sleep 3
done

if { [ "$status" = "200" ] || [ "$status" = "202" ]; } && [ -n "$session" ]; then
  tmp=$(mktemp)
  grep -v '^PHPSESSID=' "$ENV" > "$tmp" 2>/dev/null || true
  printf "PHPSESSID='%s'\n" "$session" >> "$tmp"
  mv "$tmp" "$ENV"
  chmod 600 "$ENV"
  echo "✓ logged in as $VISIONIST_EMAIL (session refreshed)."
else
  echo "✗ Could not authenticate (status=$status)${msg:+: $msg}." >&2
  exit $EX_AUTHFAIL
fi
