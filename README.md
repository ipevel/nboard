# Nboard

<div align="center">

![PHP](https://img.shields.io/badge/PHP-8.2%2B-777BB4.svg)
![MySQL](https://img.shields.io/badge/Database-MySQL-4479A1.svg)
![Redis](https://img.shields.io/badge/Cache-Redis-DC382D.svg)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

## Introduction

Nboard is a service panel written in PHP 8.2 on Laravel 12. It manages user accounts, subscription plans, orders, traffic accounting and the proxy nodes that serve them, and it exposes both a user portal and an administration console.

Subscriptions are rendered on demand in eleven client formats, node state is synchronised over a WebSocket channel, and background work runs on Laravel Horizon queues. The panel ships with Docker and Compose templates, and supports SQLite, MySQL and PostgreSQL as the primary datastore.

## Features

- **Account and billing core** — plans, orders, coupons, gift cards, invite codes and commission logs, with renewal, reset and traffic-reset handling.
- **Subscription delivery** — the same subscription is rendered for Clash, ClashMeta, SingBox, Stash, Surge, Surfboard, Shadowrocket, QuantumultX, Loon, Shadowsocks and the general URI list (`app/Protocols`).
- **Node management** — nodes, node groups, routes and per-node traffic records, plus named machine registrations with CPU, memory, disk and network load history.
- **Real-time node sync** — a Workerman WebSocket server (`php artisan ws-server start --port 8076`) pushes configuration changes to nodes instead of waiting for a poll cycle.
- **Background processing** — Laravel Horizon supervisors for order handling, traffic fetching, statistics, mail, Telegram delivery, user-activity sync and node sync.
- **Payment and messaging plugins** — bundled plugins for Alipay F2F, BTCPay, CoinPayments, Coinbase, Epay and Mgate, plus a Telegram bot for account binding, traffic queries and subscription retrieval.
- **Theming** — themes are directories containing a `dashboard.blade.php` entry point, an asset bundle and a `config.json` manifest that declares the colour scheme, background image and custom footer HTML. User-uploaded themes are supported alongside the bundled one.
- **Administration console** — a separate single-page application served from `public/assets/admin`, backed by the JSON API registered under `/api/v2` and gated by the `admin` middleware.
- **Seven UI locales** — `zh-CN`, `zh-TW`, `en-US`, `ja-JP`, `ko-KR`, `vi-VN` and `fa-IR`.
- **Deployment** — a single image with embedded Caddy on port 7001, plus Compose templates for bridge networking, host networking, 1Panel and split (per-role) topologies.

## Quick Start

### Requirements

- Docker Engine with the Compose v2 plugin
- A host port for the panel (defaults to `7001`)

Nothing else is needed on the machine: `init.sh` pulls the published image, so there is no PHP, Composer or Node build step.

### One command

```bash
git clone https://github.com/ipevel/nboard.git
cd nboard
./init.sh
```

The script pulls `ghcr.io/ipevel/nboard:latest`, starts the stack, runs the installer against SQLite and the built-in Redis, waits for the panel to answer, then prints the site URL, the administration URL and the generated administrator credentials. Save those credentials when they appear — the password is shown once.

Options:

```bash
./init.sh --port 8080                  # publish on another host port
./init.sh --admin you@example.com      # choose the administrator address
./init.sh --build                      # build the image locally instead of pulling
./init.sh --install-docker             # install Docker Engine + Compose v2 first
```

### Re-running

`init.sh` is idempotent. Once `.env` carries the `INSTALLED` flag it skips the installer and only refreshes the container. To update later, run `docker compose pull && docker compose up -d`.

### Manual Compose

To drive the stack yourself:

```bash
cp compose.sample.yaml compose.yaml
touch .env
docker compose run --rm \
    -e ENABLE_SQLITE=1 \
    -e ENABLE_REDIS=1 \
    -e ADMIN_ACCOUNT=you@example.com \
    nboard php artisan xboard:install
docker compose up -d
```

The container serves the panel through its embedded Caddy process on the published port. Keep `.env` in place between restarts; the installer rewrites it in place. MySQL and PostgreSQL installs use the same flow with the corresponding environment variables instead of `ENABLE_SQLITE`.

## Configuration

Runtime configuration lives in `.env`, created by the installer from `.env.example`:

| Key | Purpose |
| --- | --- |
| `APP_NAME` | Display name used in page titles and outbound mail |
| `APP_URL` | Public base URL; also used for the safe-mode host check |
| `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | Primary datastore |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` | Cache, queue and session backend |
| `CACHE_DRIVER`, `QUEUE_CONNECTION`, `SESSION_DRIVER` | Cache/queue/session drivers; both default to Redis |
| `ENABLE_AUTO_BACKUP_AND_UPDATE`, `GOOGLE_CLOUD_KEY_FILE`, `GOOGLE_CLOUD_STORAGE_BUCKET` | Optional Google Cloud Storage backups |

Site-level settings — application name, description, logo, theme, subscription path, administration path and mail templates — are stored in the `settings` table and edited from the administration console. Values entered there override the built-in defaults.

The Compose templates accept `RESOURCE_PROFILE` (`minimal`, `balanced`, `performance`, `auto`) to size the Octane and Horizon worker pools, and `ENABLE_CADDY`, `ENABLE_HORIZON`, `ENABLE_WEB`, `ENABLE_WS_SERVER` to select which supervisors start in split deployments.

The installer and upgrade commands are `php artisan xboard:install` and `php artisan xboard:update`; the command names are part of the deployment contract and are unchanged.

## Documentation

- [Deploy with Docker Compose](docs/en/installation/docker-compose.md)
- [Deploy with 1Panel](docs/en/installation/1panel.md)
- [Deploy with aaPanel](docs/en/installation/aapanel.md)
- [Deploy with aaPanel and Docker](docs/en/installation/aapanel-docker.md)

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 ipevel.
