# Nboard

<div align="center">

![PHP](https://img.shields.io/badge/PHP-8.2.35+-green.svg)
![Database](https://img.shields.io/badge/SQLite%20%2F%20MySQL-blue.svg)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

## Introduction

Nboard is a proxy service panel built on Laravel 12 and Octane. It provides a
Vue 3 user portal, a React admin console, a plugin system, and a Docker-based
deployment path that runs from a published image without a local PHP toolchain.

## Repository layout

This repository uses two branches with different purposes:

| Branch | Contents | Use it for |
|---|---|---|
| `master` | Application source, themes, plugins, and the image build definition | Development and building the image |
| `compose` | `compose.yaml`, deployment templates, and `.env.example` | Running a deployment |

The Quick Start below clones the `compose` branch. Cloning `master` will not
give you a `compose.yaml`; the files on `master` are the application source.

## Quick Start

Requires Docker Engine and Docker Compose v2 on the host. No PHP, Composer, or
Node.js is needed locally.

```bash
git clone -b compose --depth 1 https://github.com/ipevel/nboard.git && \
cd nboard && \
docker compose run -it --rm \
    -e ENABLE_SQLITE=true \
    -e ENABLE_REDIS=true \
    -e ADMIN_ACCOUNT=admin@example.com \
    nboard php artisan nboard:install && \
docker compose up -d
```

The installer prints a one-time administrator password and the admin path.
Save both. Then open `http://SERVER_IP:7001` for the user portal.

`ENABLE_SQLITE=true` uses an embedded database, so no separate MySQL service is
required. For MySQL, omit that variable and set the database connection in
`.env` before installing. See
[Deploy with Docker Compose](./docs/en/installation/docker-compose.md) for both
variants.

## Features

- Laravel 12 and Octane for the HTTP runtime
- React admin console and Vue 3 user portal
- Prebuilt container image, no local build required
- Plugin system with bundled payment, notification, and gateway plugins
- SQLite or MySQL storage, Redis for cache and queues

## Documentation

### Deployment

PHP **8.2.35 or later** is required inside the container. The published image
already satisfies this.

- [Deploy with Docker Compose](./docs/en/installation/docker-compose.md)
- [Deploy with 1Panel](./docs/en/installation/1panel.md)
- [Deploy with aaPanel + Docker](./docs/en/installation/aapanel-docker.md)
- [Deploy with aaPanel](./docs/en/installation/aapanel.md)

### Development

- [Plugin Development Guide](./docs/en/development/plugin-development-guide.md)
- [Device limit design](./docs/en/development/device-limit.md)
- [Performance notes](./docs/en/development/performance.md)

### Existing installations

- [Upgrade procedure](./docs/en/installation/docker-compose.md)
- [Configuration migration](./docs/en/migration/config.md)
- [Migrate from v2board dev](./docs/en/migration/v2board-dev.md)
- [Migrate from v2board 1.7.4](./docs/en/migration/v2board-1.7.4.md)
- [Migrate from v2board 1.7.3](./docs/en/migration/v2board-1.7.3.md)

Back up the database before any upgrade. Updating an existing Nboard
installation and importing data from another panel are separate procedures.

## Tech Stack

- Backend: Laravel 12, Octane, PHP 8.2+
- Admin console: React, Shadcn UI, TailwindCSS
- User portal: Vue 3, TypeScript, NaiveUI
- Storage: SQLite or MySQL; Redis for cache and queues
- Deployment: Docker and Docker Compose

## Disclaimer

This software is provided under the MIT License without warranty. Operators are
responsible for complying with the laws and regulations that apply to their own
deployment and for the security of the data they store.

## Contributing

Issues and pull requests are welcome.

## Star History

[![Stargazers over time](https://starchart.cc/ipevel/nboard.svg)](https://starchart.cc/ipevel/nboard)
