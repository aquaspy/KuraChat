# KuraChat

Private self-hosted chat as a Rails 8 PWA. One SQLite file, no Redis. Grok for replies. Optional web search (Kagi or Brave).

Messages are stored in plaintext SQLite on this server. They are sent to xAI to generate replies. If you turn **Web** on, the search query goes to the search provider configured on the server (Kagi or Brave). A share link lets anyone with the URL read that chat (no account). API keys stay on the server. This is not end-to-end encryption.

## Local

```bash
bin/setup
export XAI_API_KEY=...          # required to generate replies
export KAGI_API_KEY=...         # optional; Web toggle with Kagi (default)
# export WEB_SEARCH_PROVIDER=brave
# export BRAVE_API_KEY=...      # optional; Web toggle with Brave instead
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
# WEB_SEARCH_PROVIDER=kagi                # kagi (default) or brave
# KAGI_API_KEY=...                        # optional, for Web search with Kagi
# BRAVE_API_KEY=...                       # optional, for Web search with Brave
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

A casual grok-4.3 turn is about $0.0045. Turning **Web** on adds a search call. With **Kagi** that is Search ($12 / 1k) plus up to 3 page extracts ($4 / 1k pages), about $0.024 extra. With **Brave** it is one LLM Context request (search plus extracted page chunks; plans start around $5 / 1k, with $5 of monthly credit). The toggle defaults off.

Long chats are compacted automatically: Grok only sees the last 16 visible messages plus a short rolling summary. Old search extracts are not resent on later turns. The full transcript stays in SQLite.

The UI does not name the provider. Pick it on the VPS with `WEB_SEARCH_PROVIDER=kagi` or `brave`, plus the matching API key. Set `KAGI_EXTRACT_COUNT=1` or `0` in `.env` if you want cheaper Kagi turns. Brave tries **LLM Context** first (page extracts). The legacy Free plan does not include that endpoint, so the app falls back to **web/search** (titles, snippets, news) after one `OPTION_NOT_IN_PLAN`. Set `BRAVE_ENDPOINT=web` to skip the failed probe. Set `BRAVE_CONTEXT_TOKENS=8192` (or up to 32768) when LLM Context is on the plan. Leave `BRAVE_SEARCH_LANG` unset so tech/global queries are not stuck on Portuguese pages; set `BRAVE_COUNTRY=BR` if you want Brazilian ranking even when the UI is English. Web turns use `XAI_WEB_REASONING_EFFORT=medium` so Grok actually reads the extracts; cheap model-only turns stay on `low`.

Offline, the PWA can reopen the home page and any chat you already opened while online. Sending stays disabled until you are back online.

## Keys

| Env | What |
| --- | --- |
| `SECRET_KEY_BASE` | Session cookies (Compose). `openssl rand -hex 64` |
| `XAI_API_KEY` | Required to generate replies |
| `XAI_MODEL` | Default `grok-4.3`. `grok-4.6` is stronger at tools |
| `XAI_REASONING_EFFORT` | Default `low` (model-only turns) |
| `XAI_WEB_REASONING_EFFORT` | Default `medium` (Web turns) |
| `WEB_SEARCH_PROVIDER` | `kagi` (default) or `brave` |
| `KAGI_API_KEY` | Required for Web when the provider is Kagi |
| `KAGI_EXTRACT_COUNT` | Default `3` (0–10). Kagi only |
| `BRAVE_API_KEY` | Required for Web when the provider is Brave |
| `BRAVE_ENDPOINT` | `auto` (default), `llm`, or `web`. Free plans must use web |
| `BRAVE_CONTEXT_TOKENS` | Default `8192` (1024–32768). Brave LLM Context only |
| `BRAVE_COUNTRY` | Default `BR` when the UI is Portuguese, else `US`. `ALL` omits the filter |
| `BRAVE_SEARCH_LANG` | Unset by default. Do not pin to `pt` unless you only want Portuguese pages |
| `SIGNUP_ENABLED` | Public signup form. Turn off after the first account |
| `FORCE_SSL` | `true` when Caddy/nginx terminates HTTPS |
| `KURA_HOST` | Public hostname. Share links use this |
| `BIND` | Default `127.0.0.1:3000` |
