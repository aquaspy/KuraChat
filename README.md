# KuraChat

**A calm place to talk to Grok — on a machine you own.**

KuraChat is a self-hosted chat PWA. One SQLite file, no Redis, no third-party chat UI logging your prompts into someone else's product. You bring an [xAI](https://console.x.ai) API key. Keys stay on the server. Conversations sync across your devices because they live in *your* database.

---

## Philosophy

Public chat products are optimized for engagement and billing. KuraChat is optimized for **quality replies** and **obvious cost**.

- **Grok for writing and reasoning.** The model is xAI Grok (default `grok-4.3`). You can pin a stronger model with env if you want.
- **Web search is opt-in, per chat.** The composer has a **Web** toggle that defaults **off**. The first message locks it for that conversation (flipping later would break prompt cache). Grok still decides whether to search and how much.
- **Same bill as the model.** When Web is on, Grok uses xAI's server-side `web_search` on your existing `XAI_API_KEY`. No second search vendor.
- **Honest threat model.** Messages are plaintext SQLite on this server. They are sent to xAI to generate replies. Attached photos live on this server's disk and are **re-sent to xAI** on later turns while that message is still in the model window. Deleting a chat purges its images. Web turns also send queries through xAI's search (and from there onto the public web). The app always sets `store=false`, so xAI is not asked to keep the chat. Chat turns send a `prompt_cache_key` (the conversation id) so xAI can reuse a prompt prefix on the same server — that is billing/latency, not storing the transcript. Optional Zero Data Retention is a team setting on the xAI console, not a model name. Share links let anyone with the URL read that chat (including photos). This is **not** end-to-end encryption.
- **Same calm shell as the rest of Kura.** Cookie auth, idle lock (per device), PWA offline *reads*, Compose bound to localhost, signup you can shut off.

It sits next to [KuraNotes](https://github.com/aquaspy/KuraNotes), [KuraHome](https://github.com/aquaspy/KuraHome), [KuraCalendar](https://github.com/aquaspy/KuraCalendar), and [KuraSpend](https://github.com/aquaspy/KuraSpend) — same family, **separate** volume and database. Notes never leave your VPS; chat *must* leave toward xAI. Mixing them would be the wrong kind of clever.

---

## What you get

- Multi-user instance; each person owns many conversations
- Streaming replies over Action Cable / Turbo Streams
- Per-chat **Web** toggle (chosen on the first message, remembered in the browser for new chats)
- Attach one image per message (Grok sees it; follow-ups keep seeing it while that turn is in context)
- Optional read-only share links (`/s/...`)
- Automatic context compaction on very long threads (full transcript stays in SQLite)
- Offline: reopen chats you already opened; sending stays disabled until you are back

**What you do not get (on purpose):** generating images, a media library, per-user API keys, a model picker UI, RAG over your notes, Redis, or a bundled reverse proxy.

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

Chats live in the `kura_chat_data` volume: SQLite (`storage/production.sqlite3`) plus attached images under `storage/`. The tar below copies both.

```bash
docker compose exec web tar -C /rails/storage -cf - . > kurachat-backup.tar
```

### Shared browsers

Sign out **and** wait for the cache wipe. Until then, another person opening the PWA offline can see the previous user’s cached conversation HTML.

### Runtime (queue & YJIT)

Solid Queue stays **on** here (`SOLID_QUEUE_IN_PUMA` + `:solid_queue` adapter). Chat needs a durable worker for jobs like failing stale completions — unlike the quieter sister apps, which run Active Job `:async` with no queue supervisor.

YJIT stays **on**. Rails 8.1 enables it in production via `config.yjit`; the image also sets `RUBY_YJIT_ENABLE=1`. Leave it on.

---

## Cost

The chat bar shows a running USD total for that conversation. New turns use the amount xAI actually billed (`cost_in_usd_ticks`: model, cache, reasoning, images, and web_search). Older turns without that field fall back to the public list price plus counted `web_search` calls.

**Web does not mean “this turn will search.”** The toggle only *offers* xAI’s `web_search` tool. Grok decides whether to call it and how many times. A greeting with Web on can cost **zero extra search fees**. Each successful search is billed at **$5 / 1k calls** (~**$0.005** each) plus the tokens from the pages.

What *does* always change with Web on:

- **Thinking:** `XAI_WEB_REASONING_EFFORT` (default **`medium`**) instead of `XAI_REASONING_EFFORT` (default **`low`**). That is more reasoning tokens on *every* Web-on turn, even if Grok never searches. These envs are how hard the model thinks (`none` / `low` / `medium` / `high` / `xhigh`), not search volume. Set them on the VPS; the UI only has the Web switch.
- **Prompt cache:** the system line that says “web this turn / no web this turn” sits early in the prompt. **Flipping the toggle mid-chat changes that prefix**, so later history and photos are less likely to hit the cheap cached-input rate. Leaving Web **on for a whole research chat** (or **off** for a casual one) is cheaper than toggling every message. Leaving Web on *all the time* still pays `medium` thinking on “hi” turns — that is usually not worth it.

There is **no** search intensity setting (no off/low/medium/high for the web tool).

Cached input is cheaper than a full prompt when the conversation prefix is unchanged. xAI bills a **2× long-context** rate once a request’s prompt (including cached tokens) reaches **200k**; compaction exists to stay under that, not because the model’s window is small. The Web toggle defaults **off** and **locks after the first message** in that chat. Start a new chat to change it. Grok sees the thread until about **150k** estimated tokens. Past that, a short rolling summary plus about **32k** of recent raw messages (`CHAT_KEEP_RECENT_TOKENS`). The full transcript stays in SQLite. Attached images are resized to JPEG before Grok sees them; image tokens bill as input (and should cache on follow-ups if the prefix is stable). This is **not** Grok Imagine — KuraChat does not generate pictures.

---

## Model cost bench

This bench measures **cost only, not quality**: billed USD for the same 16 scenarios (search, reasoning, writing, code, explainers, one image, one cache probe) per model and effort level. Billed cost blends both drivers — price per token *and* verbosity — so the cheapest list price does not always win. Quality is ranked separately on blind sheets in `bench/results/`.

| Model | low | medium | high |
| --- | --- | --- | --- |
| grok-4.3 | $0.10 | $0.10 | $0.14 |
| grok-4.20-0309-reasoning \* | $0.12 | $0.15 | $0.12 |
| grok-4.5 | $0.13 | $0.20 | $0.21 |
| grok-4.6 | $0.15 | $0.25 | $0.19 |
| grok-build-0.1 \* | $0.20 | $0.22 | $0.18 |

Run 2026-09-17, billed `cost_in_usd_ticks`, single run per cell. \* `grok-build-0.1` and the 4.20 reasoning snapshots reject the effort parameter, so their columns differ only by run variance (Grok decides search counts itself). Reproduce with `bench/` — see [bench/README.md](bench/README.md).

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

## Branches

- **`master`** — development. Land and iterate here first.
- **`stable`** — tested code only. Promote from `master` once a change has been run and verified.

They sit on the same commit until the next change is under test.

---

## Environment

| Variable | What it does |
| --- | --- |
| `SECRET_KEY_BASE` | Session cookies (Compose). `openssl rand -hex 64` |
| `XAI_API_KEY` | Required to generate replies |
| `XAI_MODEL` | Default `grok-4.3`. `grok-4.6` is stronger at tools |
| `XAI_REASONING_EFFORT` | How hard Grok thinks on model-only turns. Default `low`. Not search volume. |
| `XAI_WEB_REASONING_EFFORT` | Same, but for Web-on turns. Default `medium`. Still not search volume — Grok picks how much to search. Applies even if it does not search. |
| `CHAT_REPLY_MAX_TOKENS` | Optional hard cap on reply length. Unset = no cap |
| `CHAT_WINDOW_TOKENS` | Max estimated tokens sent as Grok’s prompt. Default `150000` (under the 200k long-context price cliff) |
| `CHAT_KEEP_RECENT_TOKENS` | After compaction, how much recent raw text to keep. Default `32000` |
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
