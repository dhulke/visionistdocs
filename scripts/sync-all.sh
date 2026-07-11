#!/usr/bin/env bash
#
# sync-all.sh — main entrypoint. Downloads all new Documentos and Comunicados.
#
# It needs a way to authenticate: either a live session or login credentials in
# .env. You can also pass credentials on the command line and they'll be saved
# to .env for next time. On an expired session the sync scripts log in again and
# retry automatically; on wrong credentials this reports the problem clearly.
#
# Usage:
#   scripts/sync-all.sh                                  # use existing .env
#   scripts/sync-all.sh --email you@x.com --senha 'pw'   # save creds, then sync
#   scripts/sync-all.sh you@x.com 'pw'                   # same, positional
#
# Exit codes: 0 ok · 2 invalid credentials · 3 could-not-authenticate
#             · 4 no credentials configured · 1 other error

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
ENV="$ROOT/.env"

# ---- parse arguments -------------------------------------------------------
ARG_EMAIL=""; ARG_SENHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e|--email) ARG_EMAIL="${2:-}"; shift 2 ;;
    -p|--senha|--password) ARG_SENHA="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  if [ -z "$ARG_EMAIL" ]; then ARG_EMAIL="$1"
        elif [ -z "$ARG_SENHA" ]; then ARG_SENHA="$1"
        else echo "Unexpected argument: $1" >&2; exit 1; fi
        shift ;;
  esac
done

# ---- helper: set KEY='value' in .env (single-quote-safe) -------------------
set_env_var() {
  local key="$1" val="$2" tmp
  val=${val//\'/\'\\\'\'}                      # escape single quotes
  [ -f "$ENV" ] || { : > "$ENV"; chmod 600 "$ENV"; }
  tmp=$(mktemp)
  grep -v "^$key=" "$ENV" > "$tmp" 2>/dev/null || true
  printf "%s='%s'\n" "$key" "$val" >> "$tmp"
  mv "$tmp" "$ENV"; chmod 600 "$ENV"
}

# ---- apply credentials from args -------------------------------------------
if [ -n "$ARG_EMAIL" ] || [ -n "$ARG_SENHA" ]; then
  if [ -z "$ARG_EMAIL" ] || [ -z "$ARG_SENHA" ]; then
    echo "✗ Provide BOTH --email and --senha." >&2; exit 1
  fi
  [ -f "$ENV" ] || printf "HOST='https://brunievieira.superlogica.net'\n" > "$ENV"
  set_env_var VISIONIST_EMAIL "$ARG_EMAIL"
  set_env_var VISIONIST_SENHA "$ARG_SENHA"
  echo "✓ Credentials saved to $ENV"
fi

# ---- precondition: need a session OR credentials ---------------------------
[ -f "$ENV" ] && source "$ENV"
have_session=0; [ -n "${PHPSESSID:-}" ] && have_session=1
have_creds=0;   { [ -n "${VISIONIST_EMAIL:-}" ] && [ -n "${VISIONIST_SENHA:-}" ]; } && have_creds=1

if [ "$have_session" -eq 0 ] && [ "$have_creds" -eq 0 ]; then
  cat >&2 <<EOF
✗ No session and no credentials configured.

  This tool needs to log in to the área do condômino. Do one of:

  1) Pass your login now (it will be saved to .env for next time):
       $0 --email you@example.com --senha 'your-password'

  2) Or add these lines to $ENV:
       VISIONIST_EMAIL='you@example.com'
       VISIONIST_SENHA='your-password'

  Then run $0 again.
EOF
  exit 4
fi

# ---- run the two sync scripts ----------------------------------------------
# They auto-login on an expired session and propagate these exit codes:
#   2 invalid credentials · 3 could-not-authenticate · 4 no credentials
handle_failure() {
  local code="$1" label="$2"
  case "$code" in
    2) cat >&2 <<EOF
✗ Login rejected: invalid e-mail or password.

  Update the credentials in $ENV, or re-run with:
    $0 --email you@example.com --senha 'correct-password'
EOF
       exit 2 ;;
    3) echo "✗ Could not authenticate (server or network problem). Try again shortly." >&2
       exit 3 ;;
    4) echo "✗ No credentials configured — run: $0 --email you@example.com --senha 'pw'" >&2
       exit 4 ;;
    *) echo "✗ $label failed (exit $code)." >&2
       return "$code" ;;
  esac
}

overall=0
for step in "Documentos:sync-documentos.sh" "Comunicados:sync-comunicados.sh"; do
  label="${step%%:*}"; script="${step#*:}"
  echo; echo "═══════════ $label ═══════════"
  "$SCRIPTS_DIR/$script"
  code=$?
  if [ "$code" -ne 0 ]; then handle_failure "$code" "$label" || overall="$code"; fi
done

echo
if [ "$overall" -eq 0 ]; then
  echo "✓ All up to date."
else
  echo "✗ Finished with errors (exit $overall)." >&2
fi
exit "$overall"
