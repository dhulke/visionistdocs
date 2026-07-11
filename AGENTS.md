# AGENTS.md — Visionist condo archive

This directory is a **local mirror of the Helbor Visionist Cabral área do
condômino** (Bruni & Vieira / Superlógica): every *comunicado* (announcement)
and every *documento* (PDF) from the resident portal, kept up to date by the
shell scripts in `scripts/`.

Project root = the directory containing this file. Commands below are relative to
it; the scripts also work when called by absolute path from anywhere.

## Syncing (download new files)

One entrypoint updates both documents and comunicados, downloading only what
isn't already on disk:

```sh
./scripts/sync-all.sh
```

- **Idempotent** — safe to run anytime; prints "All up to date" when nothing is
  new. Re-run whenever the user wants the latest.
- **Authentication is automatic.** It logs in with credentials in `.env` and
  caches the session; on an expired session it re-logs in and retries by itself.
- **First run / new machine / after a password change** — provide the login once
  (saved to `.env` for next time):
  ```sh
  ./scripts/sync-all.sh --email you@example.com --senha 'password'
  ```
- **Exit codes:** `0` ok · `2` wrong e-mail/password · `3` could-not-authenticate
  (server/network, retry later) · `4` no credentials configured · `1` other.
  On `2`/`4` the script prints exactly what to fix — relay that to the user; do
  **not** guess or retype the password.

Individual syncs also exist (`scripts/sync-documentos.sh`,
`scripts/sync-comunicados.sh`) but normally just use `sync-all.sh`.

## Where files are stored

All synced content lives under **`Arquivos/`**:

```
Arquivos/Comunicados/   one .html per announcement (contains the full text) + attachments
Arquivos/Documentos/    loose documents (the top "DOCUMENTOS" accordion group)
Arquivos/Ata/  Arquivos/Assembleia/  Arquivos/Convenção/  Arquivos/Edital de convocação/  Arquivos/Regimento interno/
                     one folder per document category, PDFs named by title
```

**Comunicado filenames** are date-prefixed for chronological sorting and easy
searching, ending with the source id:

```
Arquivos/Comunicados/2024-06-17 - CONVOCAÇÃO ASSEMBLEIA GERAL EXTRAORDINÁRIA 2024 [1317].html
Arquivos/Comunicados/2024-06-17 - CONVOCAÇÃO ... [1317] - anexo 1.pdf   ← attachment, if any
```

- The `.html` body **is** the actual comunicado text (title, date, content), with
  any attachment links rewritten to the local files so it reads offline.
- Attachments are `... - anexo N.<pdf|jpg|png>`; a comunicado may have zero or many.

**Document filenames** are the document title, e.g. `Arquivos/Ata/ATA AGO 23.03.2026.pdf`.

## How to search

**By topic / title (filenames):**
```sh
find Arquivos -iname '*assembleia*'             # anything about assembleias
ls Arquivos/Comunicados | grep -i 'rateio'      # comunicados with a word in the title
```

**By date** (filenames start with `YYYY-MM-DD`, so they sort and range cleanly):
```sh
ls Arquivos/Comunicados/2024-*                  # everything from 2024
ls Arquivos/Comunicados | awk '$0 >= "2024-06" && $0 < "2024-09"'   # a date range
```

**By content of comunicados** (text lives in the HTML):
```sh
grep -rli 'garagem' Arquivos/Comunicados/       # list matching comunicados (case-insensitive)
grep -ri  'senha.*wi-?fi' Arquivos/Comunicados/ # show matching lines
```
The HTML has tags, but ordinary word/phrase searches work fine. To read one,
strip tags for a clean view: `sed -E 's/<[^>]+>//g' "<file>.html"`.

**By content of PDFs** — use Spotlight (indexes PDF + HTML text on macOS), or
`pdftotext` if installed:
```sh
mdfind -onlyin Arquivos 'inadimplência'         # full-text across the whole archive
pdftotext "Arquivos/Ata/ATA AGO 23.03.2026.pdf" - | grep -i 'quorum'   # if pdftotext present
```

When the user asks "do we have X?" or "what did the comunicado about X say?",
search first (filenames + `grep`/`mdfind`), then read the specific file. If the
archive might be stale for a *recent* request, offer to run `./scripts/sync-all.sh`
first.

## Guardrails

- **Never** commit, print, or paste the contents of `.env` — it stores the portal
  password in plaintext (kept `chmod 600`).
- **Never** hand-edit `.comunicados.idx` / `.documentos.idx` — the sync scripts
  own them (they list already-downloaded IDs).

## Requirements

`bash`, `curl`, `jq`, `perl` — see the **Installation** section of `README.md`
for per-OS setup (macOS, Linux, Windows via WSL or Git Bash). Search tips use
`grep`/`find` (always available) and optionally `mdfind` (macOS) / `pdftotext`.
