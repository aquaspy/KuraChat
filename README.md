# KuraChat

Private self-hosted chat as a Rails 8 PWA. One SQLite file, no Redis. Grok for replies. Optional Kagi search.

Messages are stored in plaintext SQLite on this server. They are sent to xAI to generate replies. If you turn **Web** on, the search query and extracted pages go to Kagi. A share link lets anyone with the URL read that chat (no account). API keys stay on the server. This is not end-to-end encryption.

## Local

```bash
bin/setup
export XAI_API_KEY=...          # required to generate replies
export KAGI_API_KEY=...         # optional; only for the Web toggle
bin/dev
```

Open http://127.0.0.1:3000

A `config/master.key` is created by `rails new` and is gitignored. Keep that file. If you cloned this repo and have no key:

```bash
rm -f config/credentials.yml.enc
EDITOR=true bin/rails credentials:edit
```

That writes a new `config/master.key`. Do not commit it.

## VPS (Docker Compose)

On the server, with Docker installed:

```bash
git clone https://github.com/aquaspy/KuraChat.git
cd KuraChat
cp .env.example .env
```

Edit `.env`. At minimum set:

```bash
SECRET_KEY_BASE=$(openssl rand -hex 64)   # paste the output into .env
KURA_HOST=chat.example.com
XAI_API_KEY=xai-...                       # from https://console.x.ai
# KAGI_API_KEY=...                        # optional, for Web search
SIGNUP_ENABLED=true                       # first account, then false
FORCE_SSL=false                           # true once Caddy/nginx terminates HTTPS
BIND=127.0.0.1:3000
```

Then:

```bash
docker compose up -d --build
```

Create the first account in the browser (http://127.0.0.1:3000), **or** from the shell:

```bash
docker compose exec web bin/rails kura:create EMAIL=you@x.com PASSWORD='at-least-8'
```

Lock signup so strangers cannot burn your API credits:

```bash
# in .env
SIGNUP_ENABLED=false
docker compose up -d
```

`docker compose restart` does **not** reload `.env`. Use `up -d`.

### Secret

Pick **one**. You do not need both.

**Compose (recommended on a VPS):**

```bash
openssl rand -hex 64
```

Put the output in `.env` as `SECRET_KEY_BASE`. No `master.key` required.

**Rails credentials** (if you already have a key, or want `rails credentials:edit`):

```bash
rm -f config/credentials.yml.enc
EDITOR=true bin/rails credentials:edit
cat config/master.key
```

Put that value in `.env` as `RAILS_MASTER_KEY`. A random hex will not decrypt the `credentials.yml.enc` that ships in git — generate a new pair as above, or use `SECRET_KEY_BASE` instead.

Losing the key does not lose chats. It only invalidates session cookies. Generate a new one and users sign in again.

### Users on the server

Same rake tasks as KuraNotes:

```bash
docker compose exec web bin/rails kura:users
docker compose exec web bin/rails kura:create EMAIL=you@x.com PASSWORD='at-least-8'
docker compose exec web bin/rails kura:password EMAIL=you@x.com PASSWORD='new-secret'
```

`kura:password` is the admin reset. There is no email recovery.

### Proxy (Caddy or nginx)

Nothing is bundled. The app listens on `127.0.0.1:3000` and does not bind 80/443. Point your own Caddy or nginx at that address, set `FORCE_SSL=true` in `.env`, then `docker compose up -d`.

Action Cable needs a WebSocket upgrade on `/cable`. If HTTPS is terminated in front, `FORCE_SSL=true` is required or the socket is rejected and the UI stays on “Thinking…”.

Caddy:

```
chat.example.com {
  reverse_proxy 127.0.0.1:3000
}
```

nginx:

```
location /cable {
  proxy_pass http://127.0.0.1:3000;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_read_timeout 3600;
}

location / {
  proxy_pass http://127.0.0.1:3000;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

### Backup

Chats live in the `kura_chat_data` volume (`storage/production.sqlite3`). Back that up.

```bash
docker compose exec web tar -C /rails/storage -cf - . > kurachat-backup.tar
```

Shared browsers: Sign out **and** wait for the cache wipe. Until then another person who opens the PWA offline can see the previous user’s cached conversation HTML.

### Cost

A casual grok-4.3 turn is about $0.0045. Turning **Web** on adds Kagi Search ($12 / 1k) plus up to 3 page extracts ($4 / 1k pages), about $0.024 extra. The toggle defaults off.

Long chats are compacted automatically: Grok only sees the last 16 visible messages plus a short rolling summary. Old Kagi extracts are not resent on later turns. The full transcript stays in SQLite.

Set `KAGI_EXTRACT_COUNT=1` or `0` in `.env` if you want cheaper Web turns.

## Keys

| Env | What |
| --- | --- |
| `SECRET_KEY_BASE` | Session cookies (Compose). `openssl rand -hex 64` |
| `XAI_API_KEY` | Required to generate replies |
| `XAI_MODEL` | Default `grok-4.3` |
| `XAI_REASONING_EFFORT` | Default `low` |
| `KAGI_API_KEY` | Required only when someone uses Web |
| `KAGI_EXTRACT_COUNT` | Default `3` (0–10) |
| `SIGNUP_ENABLED` | Public signup form. Turn off after the first account |
| `FORCE_SSL` | `true` when Caddy/nginx terminates HTTPS |
| `KURA_HOST` | Public hostname. Share links use this |
| `BIND` | Default `127.0.0.1:3000` |
