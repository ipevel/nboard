#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Nboard one-command Docker installer
# ---------------------------------------------------------------------------
# Pulls the published image, starts the stack and runs the installer for you.
# No PHP, Composer or Node toolchain is required on the host.
#
#   ./init.sh                       # pull ghcr.io/ipevel/nboard:latest and start
#   ./init.sh --port 8080           # publish on another host port
#   ./init.sh --admin me@site.com   # choose the administrator address
#   ./init.sh --build               # build the image locally instead of pulling
#   ./init.sh --install-docker      # install Docker Engine + Compose v2 first
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

say()  { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

# --- 0. Guard: must run from a real nboard checkout -------------------------
[[ -f compose.sample.yaml ]] || die "compose.sample.yaml not found. Run this script from the nboard repository root."

# --- 1. Parse flags ---------------------------------------------------------
PORT="${NB_PORT:-7001}"
ADMIN_ACCOUNT="${ADMIN_ACCOUNT:-}"
DO_BUILD=0
DO_INSTALL_DOCKER=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)           PORT="${2:?--port needs a value}"; shift 2 ;;
        --admin)          ADMIN_ACCOUNT="${2:?--admin needs a value}"; shift 2 ;;
        --build)          DO_BUILD=1; shift ;;
        --install-docker) DO_INSTALL_DOCKER=1; shift ;;
        -h|--help)        sed -n '2,15p' "$0"; exit 0 ;;
        *)                die "unknown argument: $1" ;;
    esac
done

# --- 2. Docker + Compose v2 -------------------------------------------------
install_docker() {
    say "Installing Docker Engine and the Compose plugin..."
    if [[ -f /etc/debian_version ]]; then
        curl -fsSL https://get.docker.com | sh
    elif [[ -f /etc/redhat-release ]]; then
        curl -fsSL https://get.docker.com | sh
    else
        die "Unsupported distribution for automatic Docker installation. Install Docker manually, then re-run without --install-docker."
    fi
    systemctl enable --now docker || true
}

if ! command -v docker >/dev/null 2>&1; then
    if [[ "$DO_INSTALL_DOCKER" == "1" ]]; then
        install_docker
    else
        die "Docker is not installed. Re-run with --install-docker to install it, or install Docker Engine + Compose v2 yourself."
    fi
fi

if ! docker compose version >/dev/null 2>&1; then
    if [[ "$DO_INSTALL_DOCKER" == "1" ]]; then
        install_docker
    fi
    docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required ('docker compose'). Install it and re-run."
fi

docker info >/dev/null 2>&1 || die "Cannot talk to the Docker daemon. Start Docker (or fix permissions) and re-run."

# --- 3. Resolve the image ---------------------------------------------------
if [[ "$DO_BUILD" == "1" ]]; then
    IMAGE="nboard:local"
    say "Building the image locally as ${IMAGE} (this takes several minutes)..."
    docker build -t "$IMAGE" "$REPO_DIR"
else
    IMAGE="${NB_IMAGE:-ghcr.io/ipevel/nboard:latest}"
    # A registry-less reference in the environment (e.g. nboard:local from an older
    # run) would silently use a stale local image. Ignore it unless --build was given.
    if [[ "$IMAGE" != *"/"* ]]; then
        warn "ignoring NB_IMAGE=${IMAGE} (no registry host); using the published image instead. Pass --build to build locally."
        IMAGE="ghcr.io/ipevel/nboard:latest"
    fi
    say "Pulling ${IMAGE}..."
    docker pull "$IMAGE" || die "Could not pull ${IMAGE}. Check the tag, or build locally with --build."
fi

# --- 4. Prepare compose.yaml and .env --------------------------------------
if [[ ! -f compose.yaml ]]; then
    cp compose.sample.yaml compose.yaml
    say "Created compose.yaml from the sample."
fi

[[ -f .env ]] || : > .env

# Publish on the requested port.
python3 - "$PORT" <<'PY'
import re, sys
port = sys.argv[1]
path = "compose.yaml"
s = open(path, encoding="utf-8").read()
s2, n = re.subn(r'-\s*"[0-9]+:7001"', f'- "{port}:7001"', s, count=1)
if n == 0:
    s2, n = re.subn(r'-\s*[0-9]+:7001', f'- "{port}:7001"', s, count=1)
if n:
    open(path, "w", encoding="utf-8").write(s2)
    print(f"Publishing on host port {port}.")
else:
    print("Notice: no 7001 mapping found in compose.yaml; leaving ports untouched.")
PY

export NB_IMAGE="$IMAGE"

# --- 5. Start the stack -----------------------------------------------------
say "Starting the stack..."
docker compose --env-file .env up -d

# --- 6. First-run install (non-interactive) --------------------------------
installed="$(grep -cE '^INSTALLED=(1|true)$' .env || true)"
install_output=""

if [[ "$installed" == "0" ]]; then
    if [[ -z "$ADMIN_ACCOUNT" ]]; then
        ADMIN_ACCOUNT="admin@example.com"
        say "No --admin given; using ${ADMIN_ACCOUNT} (change the password after the first login)."
    fi
    say "Running the installer (SQLite + built-in Redis)..."
    set +e
    install_output="$(docker compose --env-file .env run --rm \
        -e ENABLE_SQLITE=1 \
        -e ENABLE_REDIS=1 \
        -e ADMIN_ACCOUNT="$ADMIN_ACCOUNT" \
        nboard php artisan xboard:install --no-interaction 2>&1)"
    install_status=$?
    set -e
    printf '%s\n' "$install_output" | tail -20
    [[ $install_status -eq 0 ]] || die "The installer exited with status ${install_status}. Review the output above."
    grep -qE '^INSTALLED=(1|true)$' .env || die "The installer finished but .env has no INSTALLED flag. Check the container logs: docker compose logs nboard"
else
    say "Already installed (INSTALLED flag present in .env); skipping the installer."
fi

# --- 7. Health check --------------------------------------------------------
say "Waiting for the panel to answer..."
healthy=0
for _ in $(seq 1 40); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)"
    if [[ "$code" == "200" || "$code" == "302" ]]; then healthy=1; break; fi
    sleep 3
done
[[ "$healthy" == "1" ]] || warn "The panel did not answer on port ${PORT} within two minutes. Check: docker compose logs -f nboard"

# --- 8. Summary -------------------------------------------------------------
admin_path=""
if [[ -n "$install_output" ]]; then
    admin_path="$(printf '%s\n' "$install_output" | grep -oE '你的站点/[A-Za-z0-9]+' | awk -F/ '{print $NF}' | head -1)"
fi
[[ -n "$admin_path" ]] || admin_path="$(docker compose exec -T nboard php -r 'echo hash("crc32b", config("app.key"));' 2>/dev/null | tr -d '\r' || true)"

public_ip="$(curl -s --max-time 5 https://api.ipify.org || true)"
[[ -n "$public_ip" ]] || public_ip="<your-server-ip>"

say ""
say "----------------------------------------------------------------"
say " Nboard is running"
say "----------------------------------------------------------------"
say " Site      http://${public_ip}:${PORT}/"
if [[ -n "$admin_path" ]]; then
    say " Admin     http://${public_ip}:${PORT}/${admin_path}"
else
    say " Admin     http://${public_ip}:${PORT}/<admin-path>   (see the installer output above)"
fi
say " Local     http://127.0.0.1:${PORT}/"
say ""
if [[ -n "$install_output" ]]; then
    printf '%s\n' "$install_output" | grep -E '管理员邮箱|管理员密码' || true
fi
say ""
say "Save the administrator credentials now. They are printed once,"
say "and live in .env plus the database once you change them."
say "----------------------------------------------------------------"
