# Visionist — arquivo do condomínio

Local archive of documents from the Helbor Visionist Cabral área do condômino
(Bruni & Vieira / Superlógica).

## Layout

```
visionist/
├── Arquivos/                # all synced content lives here:
│   ├── Comunicados/      #   every comunicado as an .html file (text) + its attachments
│   ├── Documentos/       #   loose documents (top "DOCUMENTOS" accordion group)
│   └── Assembleia/  Ata/  Convenção/  "Edital de convocação"/  "Regimento interno"/
│                         #   one folder per non-empty accordion category
├── scripts/
│   ├── sync-all.sh         # ← main entrypoint (run this)
│   ├── sync-documentos.sh  # documents sync (called by sync-all)
│   ├── sync-comunicados.sh # comunicados sync (called by sync-all)
│   └── login.sh            # obtains a fresh session (called automatically)
├── .env                  # credentials + current session (chmod 600, never commit)
├── .comunicados.idx      # IDs already downloaded (one per line)
└── .documentos.idx
```

## Updating the archive

```sh
cd ~/Projects/visionist
./scripts/sync-all.sh
```

That's it. `sync-all.sh` runs both syncs; each lists everything on the server,
compares it against the matching `.idx` file, and downloads **only what's new**.
Safe to re-run anytime — if nothing is new it prints "All up to date".

## Credentials & sessions

The tool logs in with `VISIONIST_EMAIL` / `VISIONIST_SENHA` from `.env` and
caches the resulting session as `PHPSESSID`. You normally never touch these:

- **Expired session** → the sync scripts detect it, call `login.sh` to refresh,
  and retry automatically.
- **First-time / new machine** → pass your login once; it's saved to `.env`:
  ```sh
  ./scripts/sync-all.sh --email you@example.com --senha 'your-password'
  ```
- **Wrong e-mail/password** → it stops and tells you to fix the credentials
  (it never silently caches a bad session).
- **No session and no credentials** → it explains how to provide them.

### Exit codes

| code | meaning |
|------|---------|
| 0 | success |
| 2 | invalid e-mail/password |
| 3 | could not authenticate (server/network) — try again shortly |
| 4 | no credentials configured |
| 1 | other error |

`.env` holds your password in plain text, so it's kept `chmod 600` (owner-only).
Don't commit it.

## Requirements

`bash`, `curl`, `jq`, `perl` (`brew install jq`).
