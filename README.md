# KuraChat

**A calm place to talk to Grok — on a machine you own.**

KuraChat is a self-hosted chat PWA. One SQLite file, no Redis, no third-party chat UI logging your prompts into someone else's product. You bring an [xAI](https://console.x.ai) API key; optionally you bring [Kagi](https://kagi.com) or [Brave](https://brave.com/search/api/) for web search. Keys stay on the server. Conversations sync across your devices because they live in *your* database.

---

## Philosophy

Public chat products are optimized for engagement and billing. KuraChat is optimized for **quality replies** and **obvious cost**.

- **Grok for writing and reasoning.** The model is xAI Grok (default `grok-4.3`). You can pin a stronger model with env if you want.
- **Web search is opt-in, per turn.** The composer has a **Web** toggle that defaults **off**. A casual message is one model call. Research is a deliberate switch — and a deliberate dollar.
- **Your search provider, not theirs.** When Web is on, search goes to Kagi or Brave as *you* configured on the VPS — not a generic Bing layer buried in the model.
- **Honest threat model.** Messages are plaintext SQLite on this server. They are sent to xAI to generate replies. Web turns also send a query (and page extracts) to the search provider. Share links let anyone with the URL read that chat. This is **not** end-to-end encryption.
- **Same calm shell as the rest of Kura.** Cookie auth, idle lock, PWA offline *reads*, Compose bound to localhost, signup you can shut off.

It sits next to [KuraNotes](https://github.com/aquaspy/KuraNotes), [KuraHome](https://github.com/aquaspy/KuraHome), [KuraCalendar](https://github.com/aquaspy/KuraCalendar), and [KuraSpend](https://github.com/aquaspy/KuraSpend) — same family, **separate** volume and database. Notes never leave your VPS; chat *must* leave toward xAI. Mixing them would be the wrong kind of clever.

---

## What you get

- Multi-user instance; each person owns many conversations
- Streaming replies over Action Cable / Turbo Streams
- Per-turn **Web** toggle (remembered in the browser)
- Optional read-only share links (`/s/...`)
- Automatic context compaction on long threads (full transcript stays in SQLite)
- Offline: reopen chats you already opened; sending stays disabled until you are back

**What you do not get (on purpose):** images/vision in v1, per-user API keys, a model picker UI, RAG over your notes, Redis, or a bundled reverse proxy.

---

## Self-host (Docker Compose)

```bash
git clone https://github.com/aquaspy/KuraChat.git
cd KuraChat
cp .env.example .env
```

Edit `.env`. At minimum:

```bash
SECRET_KEY_BASE=          # paste: openssl rand -hex 64
KURA_HOST=chat.example.com
XAI_API_KEY=xai-...       # from https://console.x.ai
SIGNUP_ENABLED=true       # first account, then false
FORCE_SSL=false           # true once HTTPS terminates in front
BIND=127.0.0.1:3000

# Optional web search (provider is chosen here — the UI only toggles on/off)
# WEB_SEARCH_PROVIDER=kagi   # or brave
# KAGI_API_KEY=...
# BRAVE_API_KEY=...
```

Then:

```bash
docker compose up -d --build
```

Create the first account in the browser (`http://127.0.0.1:3000`), or:

```bash
docker compose exec web bin/rails kura:create EMAIL=you@example.com PASSWORD='at-least-8'
```

**Lock signup** so strangers cannot burn your API credits:

```bash
# in .env
SIGNUP_ENABLED=false
docker compose up -d
```

> **Important:** `docker compose restart` does **not** reload `.env`. Use `docker compose up -d`.

### Secrets

Pick **one**. You do not need both.

| Approach | When | How |
| --- | --- | --- |
| **`SECRET_KEY_BASE`** (recommended) | Compose / VPS | `openssl rand -hex 64` → `.env` |
| **`RAILS_MASTER_KEY`** | Rails credentials | Regenerate with `EDITOR=true bin/rails credentials:edit`, put `config/master.key` in `.env` |

A random hex will not decrypt the shipped `credentials.yml.enc`. Losing the key does not lose chats — only session cookies.

### Reverse proxy (Caddy or nginx)

The app listens on `BIND` (default `127.0.0.1:3000`) and does not claim 80/443. Point your proxy there, set `FORCE_SSL=true`, then `docker compose up -d`.

**Action Cable needs a WebSocket upgrade on `/cable`.** If HTTPS terminates in front and `FORCE_SSL` is false, the socket is rejected and the UI sticks on “Thinking…”.

**Caddy:**

```
chat.example.com {
  reverse_proxy 127.0.0.1:3000
}
```

**nginx:**

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

### Users on the server

No email recovery — reset from the box:

```bash
docker compose exec web bin/rails kura:users
docker compose exec web bin/rails kura:create EMAIL=you@example.com PASSWORD='at-least-8'
docker compose exec web bin/rails kura:password EMAIL=you@example.com PASSWORD='new-secret'
```

### Backup

Chats live in the `kura_chat_data` volume (`storage/production.sqlite3`).

```bash
docker compose exec web tar -C /rails/storage -cf - . > kurachat-backup.tar
```

### Shared browsers

Sign out **and** wait for the cache wipe. Until then, another person opening the PWA offline can see the previous user’s cached conversation HTML.

---

## Cost (rough)

A casual grok-4.3 turn is about **$0.0045**. Turning **Web** on adds a search call.

| Provider | Extra ballpark per Web turn |
| --- | --- |
| **Kagi** | Search ($12 / 1k) + up to 3 page extracts ($4 / 1k pages) ≈ **$0.024** |
| **Brave** | One request: LLM Context when the key’s plan includes it, otherwise Web Search (~$5 / 1k on the Search plan, with monthly credit) |

The Web toggle defaults **off**. Long chats are compacted automatically: Grok sees the last 16 visible messages plus a short rolling summary. Old search extracts are not resent. The full transcript stays in SQLite.

The UI does not name the provider. Pick it on the VPS with `WEB_SEARCH_PROVIDER=kagi` or `brave`, plus the matching API key. Set `KAGI_EXTRACT_COUNT=1` or `0` for cheaper Kagi turns.

Search region follows the browser `Accept-Language` (`pt-BR` → Brazil, `pt-PT` → Portugal, `en-GB` → UK; bare Portuguese defaults to **BR**; bare English is left unset). Pin everyone with `SEARCH_REGION=BR`, or per provider with `KAGI_REGION` / `BRAVE_COUNTRY` (`ALL` turns the filter off). Leave `BRAVE_SEARCH_LANG` unset so global/tech queries are not stuck on Portuguese pages. Web turns use `XAI_WEB_REASONING_EFFORT=medium` so Grok actually reads extracts; model-only turns stay on `low`.

### Brave plans

Any Brave key that can call Web Search works. You do not set the plan in the UI. `BRAVE_ENDPOINT=auto` (default) probes what the key allows:

| Plan | What KuraChat uses |
| --- | --- |
| Search (paid, includes LLM Context) | `/llm/context` — extracted page chunks |
| Legacy Free, or any plan without LLM Context | `/web/search` — titles, snippets, news |

If a field is not in the plan, the client retries without optional flags, then tries the other endpoint. Set `BRAVE_ENDPOINT=web` or `llm` only to skip the probe.

---

## Local development

```bash
bin/setup
export XAI_API_KEY=...          # required to generate replies
export KAGI_API_KEY=...         # optional; Web with Kagi (default)
# export WEB_SEARCH_PROVIDER=brave
# export BRAVE_API_KEY=...
bin/dev
```

Open http://127.0.0.1:3000

If you cloned without a `master.key`:

```bash
rm -f config/credentials.yml.enc
EDITOR=true bin/rails credentials:edit
```

Do not commit `config/master.key`.

---

## Environment

| Variable | What it does |
| --- | --- |
| `SECRET_KEY_BASE` | Session cookies (Compose). `openssl rand -hex 64` |
| `XAI_API_KEY` | Required to generate replies |
| `XAI_MODEL` | Default `grok-4.3`. `grok-4.6` is stronger at tools |
| `XAI_REASONING_EFFORT` | Default `low` (model-only turns) |
| `XAI_WEB_REASONING_EFFORT` | Default `medium` (Web turns) |
| `WEB_SEARCH_PROVIDER` | `kagi` (default) or `brave` |
| `KAGI_API_KEY` | Required for Web when provider is Kagi |
| `KAGI_EXTRACT_COUNT` | Default `3` (0–10). Kagi only |
| `SEARCH_REGION` | Optional pin for both providers (`BR`, `PT`, `ALL`, …) |
| `KAGI_REGION` | Overrides `SEARCH_REGION` for Kagi |
| `BRAVE_API_KEY` | Required for Web when provider is Brave |
| `BRAVE_ENDPOINT` | `auto` (default), or `llm` / `web` |
| `BRAVE_CONTEXT_TOKENS` | Default `8192` (1024–32768). LLM Context only |
| `BRAVE_COUNTRY` | Overrides `SEARCH_REGION` for Brave |
| `BRAVE_SEARCH_LANG` | Unset by default — do not pin to `pt` unless you only want Portuguese pages |
| `SIGNUP_ENABLED` | Public signup. Turn off after the first account |
| `FORCE_SSL` | `true` when Caddy/nginx terminates HTTPS |
| `KURA_HOST` | Public hostname. Share links use this |
| `BIND` | Default `127.0.0.1:3000` |

---

## Sister apps

| App | Role |
| --- | --- |
| [KuraNotes](https://github.com/aquaspy/KuraNotes) | Private notes |
| [KuraHome](https://github.com/aquaspy/KuraHome) | Quiet start-page / homepage |
| [KuraCalendar](https://github.com/aquaspy/KuraCalendar) | Personal calendar & birthdays |
| [KuraSpend](https://github.com/aquaspy/KuraSpend) | Subscriptions & daily spend |
