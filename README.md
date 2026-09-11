# KuraChat

**A calm place to talk to Grok — on a machine you own.**

KuraChat is a self-hosted chat PWA. One SQLite file, no Redis, no third-party chat UI logging your prompts into someone else's product. You bring an [xAI](https://console.x.ai) API key. Keys stay on the server. Conversations sync across your devices because they live in *your* database.

---

## Philosophy

Public chat products are optimized for engagement and billing. KuraChat is optimized for **quality replies** and **obvious cost**.

- **Grok for writing and reasoning.** The model is xAI Grok (default `grok-4.3`). You can pin a stronger model with env if you want.
- **Web search is opt-in, per turn.** The composer has a **Web** toggle that defaults **off**. A casual message is one model call. Research is a deliberate switch — and a deliberate dollar. Grok decides whether to search and how much.
- **Same bill as the model.** When Web is on, Grok uses xAI's server-side `web_search` on your existing `XAI_API_KEY`. No second search vendor.
- **Honest threat model.** Messages are plaintext SQLite on this server. They are sent to xAI to generate replies. Web turns also send queries through xAI's search (and from there onto the public web). The app always sets `store=false`, so xAI is not asked to keep the chat. Optional Zero Data Retention is a team setting on the xAI console, not a model name. Share links let anyone with the URL read that chat. This is **not** end-to-end encryption.
- **Same calm shell as the rest of Kura.** Cookie auth, idle lock (per device), PWA offline *reads*, Compose bound to localhost, signup you can shut off.

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

### Runtime (queue & YJIT)

Solid Queue stays **on** here (`SOLID_QUEUE_IN_PUMA` + `:solid_queue` adapter). Chat needs a durable worker for jobs like failing stale completions — unlike the quieter sister apps, which run Active Job `:async` with no queue supervisor.

YJIT stays **on**. Rails 8.1 enables it in production via `config.yjit`; the image also sets `RUBY_YJIT_ENABLE=1`. Leave it on.

---

## Cost (rough)

A casual grok-4.3 turn is about **$0.0045**. Turning **Web** on lets Grok call xAI `web_search` (~**$5 / 1k calls**, so about **$0.005** per search) plus the extra tokens from browsing. Grok decides how many searches, if any. There is **no** search intensity setting (no off/low/medium/high for the web tool).

The Web toggle defaults **off**. Long chats are compacted automatically: Grok sees the last 16 visible messages plus a short rolling summary. The full transcript stays in SQLite.

`XAI_REASONING_EFFORT` / `XAI_WEB_REASONING_EFFORT` are **how hard the model thinks** (`none` / `low` / `medium` / `high` / `xhigh`), not how much it searches. Defaults: `low` without Web, `medium` with Web so Grok can actually use what it found. Set them on the VPS; the UI only has the Web switch.

---

## Local development

```bash
bin/setup
export XAI_API_KEY=...          # required to generate replies
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
| `XAI_REASONING_EFFORT` | How hard Grok thinks on model-only turns. Default `low`. Not search volume. |
| `XAI_WEB_REASONING_EFFORT` | Same, but for Web-on turns. Default `medium`. Still not search volume — Grok picks how much to search. |
| `CHAT_REPLY_MAX_TOKENS` | Optional hard cap on reply length. Unset = no cap |
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
