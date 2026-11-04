#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Nboard 更新脚本
# ---------------------------------------------------------------------------
# 一个脚本覆盖两种部署形态：
#   * git 部署：目录内存在 .git，走代码拉取 + 依赖更新 + xboard:update；
#   * 镜像部署：目录内没有 .git（纯 compose 目录），拉取最新镜像并重建容器。
#
# 用法见 `bash update.sh --help`。
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 镜像的默认值，可通过环境变量覆盖。
DEFAULT_IMAGE="ghcr.io/ipevel/nboard:latest"
HEALTH_TIMEOUT=180

say()  { printf '%s\n' "$*"; }
info() { printf '[update] %s\n' "$*"; }
warn() { printf '[update] 警告：%s\n' "$*" >&2; }
die()  { printf '[update] 错误：%s\n' "$*" >&2; exit 1; }

# 统一的命令执行入口：--dry-run 时只打印，不落盘。
run() {
  if (( DRY_RUN )); then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

usage() {
  cat <<'EOF'
用法：
  bash update.sh [选项]

模式（脚本自动判断，无需手动选择）：
  git 部署        目录内存在 .git：拉取 origin/master、更新 Composer 依赖、执行 xboard:update。
  镜像部署        目录内没有 .git：拉取镜像、重建容器、等待面板响应。

选项：
  --build         从脚本所在目录的源码本地构建镜像，跳过拉取（目录内需有 Dockerfile）
  --dry-run       只打印将要执行的命令，不实际执行
  -h, --help      显示本帮助

环境变量：
  NB_IMAGE        镜像地址，默认 ghcr.io/ipevel/nboard:latest
  PORT            健康检查使用的本地端口，默认 7001

退出码：
  0   更新成功
  1   更新失败

示例：
  bash update.sh
  bash update.sh --build
  NB_IMAGE=ghcr.io/ipevel/nboard:new bash update.sh --dry-run
EOF
}

DO_BUILD=0
DRY_RUN=0

while (( $# > 0 )); do
  case "$1" in
    --build)   DO_BUILD=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "未知参数：$1（执行 bash update.sh --help 查看用法）" ;;
  esac
done

# ---------------------------------------------------------------------------
# 部署目录与 compose 文件定位
# ---------------------------------------------------------------------------
# 优先使用当前工作目录；在源码仓库里执行时也可能停留在仓库根，两者都需要覆盖。
find_compose_file() {
  local dir="$1" name
  for name in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [[ -f "$dir/$name" ]]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

# 目录判定优先级：当前目录是 git 仓库则固定用它；否则优先当前目录的 compose 部署，
# 再回落到脚本所在目录，保证「站在部署目录执行」与「在源码仓库执行」都能工作。
if [[ -d "$PWD/.git" ]]; then
  WORK_DIR="$PWD"
elif find_compose_file "$PWD" >/dev/null; then
  WORK_DIR="$PWD"
elif [[ -d "$SCRIPT_DIR/.git" ]] || find_compose_file "$SCRIPT_DIR" >/dev/null; then
  WORK_DIR="$SCRIPT_DIR"
else
  WORK_DIR="$PWD"
fi
cd "$WORK_DIR"

# 切换目录后重新定位，保证后续命令与 compose 文件在同一目录。
COMPOSE_FILE=""
if COMPOSE_FILE="$(find_compose_file "$WORK_DIR")"; then
  COMPOSE_FILE="$(basename "$COMPOSE_FILE")"
fi

# ---------------------------------------------------------------------------
# 通用工具函数
# ---------------------------------------------------------------------------
resolve_image() {
  local image="${NB_IMAGE:-}"

  # NB_IMAGE 未导出时回落到部署目录 .env，与 compose 的解析顺序保持一致。
  if [[ -z "$image" && -f .env ]]; then
    image="$(grep -E '^[[:space:]]*NB_IMAGE=' .env 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
    image="${image%\"}"; image="${image#\"}"
    image="${image%\'}"; image="${image#\'}"
    image="$(printf '%s' "$image" | tr -d '[:space:]')"
  fi

  [[ -n "$image" ]] || image="$DEFAULT_IMAGE"
  printf '%s\n' "$image"
}

image_id() {
  docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

# 从 compose 的规范化输出里取某个服务实际引用的镜像（变量已展开）。
service_image() {
  local service="$1"
  docker compose -f "$COMPOSE_FILE" config 2>/dev/null | awk -v svc="$service" '
    /^services:[[:space:]]*$/ { in_services = 1; next }
    /^[^[:space:]]/ { in_services = 0 }
    in_services && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
      cur = $0;
      sub(/^[[:space:]]+/, "", cur);
      sub(/:.*/, "", cur);
      next;
    }
    in_services && cur == svc && /^[[:space:]]+image:[[:space:]]*/ {
      sub(/^[[:space:]]+image:[[:space:]]*/, "");
      sub(/[[:space:]]+$/, "");
      print;
      exit;
    }
  '
}

require_compose() {
  command -v docker >/dev/null 2>&1 || die "未找到 docker 命令，请先安装 Docker Engine。"
  docker compose version >/dev/null 2>&1 || die "未找到 Docker Compose v2 插件（docker compose），请先安装。"
  [[ -n "$COMPOSE_FILE" ]] || die "当前目录没有 compose 文件（compose.yaml / compose.yml / docker-compose.yaml / docker-compose.yml），无法执行镜像更新。"
}

wait_for_http() {
  local url="http://127.0.0.1:${PORT:-7001}"
  local deadline=$(( SECONDS + HEALTH_TIMEOUT ))
  local code

  info "等待面板响应：$url（最长 ${HEALTH_TIMEOUT} 秒）"
  while (( SECONDS < deadline )); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      info "面板已响应，HTTP 状态码 $code"
      return 0
    fi
    sleep 3
  done

  return 1
}

# ---------------------------------------------------------------------------
# git 部署：保留原有行为
# ---------------------------------------------------------------------------
add_safe_directory() {
  local dir="$1"
  git config --global --get-all safe.directory | grep -Fx "$dir" >/dev/null || \
    git config --global --add safe.directory "$dir"
}

update_from_git() {
  local repo_root
  repo_root="$(pwd)"

  info "检测到 .git，按 git 部署流程更新：$repo_root"
  command -v git >/dev/null 2>&1 || die "未找到 git 命令，请先安装 git。"
  command -v php >/dev/null 2>&1 || die "未找到 php 命令，git 部署需要本机 PHP 环境。"
  command -v wget >/dev/null 2>&1 || die "未找到 wget 命令，无法下载 composer.phar。"

  if (( DRY_RUN )); then
    say "[dry-run] git config --global --add safe.directory $repo_root"
    say "[dry-run] git config --global --add safe.directory $repo_root/public/assets/admin"
    say "[dry-run] git fetch --all && git reset --hard origin/master && git pull origin master"
    say "[dry-run] rm -rf composer.lock composer.phar"
    say "[dry-run] wget https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar"
    say "[dry-run] php composer.phar update -vvv"
    say "[dry-run] git submodule update --init --recursive --force"
    say "[dry-run] php artisan xboard:update"
    return 0
  fi

  add_safe_directory "$repo_root"
  add_safe_directory "$repo_root/public/assets/admin"

  git fetch --all && git reset --hard origin/master && git pull origin master
  rm -rf composer.lock composer.phar
  wget https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar
  php composer.phar update -vvv
  git submodule update --init --recursive --force
  php artisan xboard:update

  if [ -f "/etc/init.d/bt" ] || [ -f "/.dockerenv" ]; then
    chown -R www:www "$(pwd)"
  fi

  if [ -d ".docker/.data" ]; then
    chmod -R 777 .docker/.data
  fi
}

# ---------------------------------------------------------------------------
# 镜像部署：拉取镜像 + 重建容器 + 健康检查
# ---------------------------------------------------------------------------
update_from_image() {
  local image before_id after_id
  local services primary ref target
  local targets=()

  require_compose
  command -v curl >/dev/null 2>&1 || die "未找到 curl 命令，健康检查需要它。"

  image="$(resolve_image)"
  info "部署目录：$(pwd)"
  info "compose 文件：$COMPOSE_FILE"
  info "目标镜像：$image"

  services="$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null)" || \
    die "无法解析 compose 文件 $COMPOSE_FILE，请先确认其语法正确（docker compose config）。"

  # 只重建面板相关服务；compose 里检测不到这些服务名时整体 up -d，不对服务名做猜测。
  for target in nboard web horizon ws-server; do
    if printf '%s\n' "$services" | grep -qx "$target"; then
      targets+=("$target")
      [[ -n "${primary:-}" ]] || primary="$target"
    fi
  done
  [[ -n "${primary:-}" ]] || primary="$(printf '%s\n' "$services" | head -n 1)"

  # 更新前状态：镜像 ID 与容器列表，用于更新后对比。
  before_id="$(image_id "$image")"
  [[ -n "$before_id" ]] || before_id="(本地不存在)"
  info "更新前镜像 ID：$before_id"
  say "--- 更新前容器状态 ---"
  docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || true

  if (( DO_BUILD )); then
    [[ -f "$SCRIPT_DIR/Dockerfile" ]] || die "--build 需要在源码目录执行：$SCRIPT_DIR 下没有 Dockerfile。"
    info "从源码本地构建镜像：$SCRIPT_DIR"
    if ! run docker build -t "$image" "$SCRIPT_DIR"; then
      die "镜像构建失败（$image），请查看上方 docker build 输出。"
    fi
  else
    info "拉取镜像：$image"
    if ! run docker pull "$image"; then
      die "镜像拉取失败（$image）。请检查网络、镜像名或仓库访问权限，也可改用 --build 从源码构建。"
    fi
  fi

  # compose 里引用的镜像与目标镜像不一致时，不擅自修改 compose，只做必要的本地打标签。
  if [[ -n "$COMPOSE_FILE" && -n "$primary" ]]; then
    ref="$(service_image "$primary")"
    if [[ -n "$ref" && "$ref" != "$image" ]]; then
      warn "compose 文件里 $primary 服务引用的镜像是 $ref，与本次更新的 $image 不一致；脚本不会修改 compose 文件。"
      if docker image inspect "$ref" >/dev/null 2>&1; then
        info "本地已存在 $ref，将其指向刚获取的镜像，保证重建后运行的就是新版本。"
        run docker tag "$image" "$ref"
      else
        warn "本地没有 $ref，docker compose 会按 compose 文件的引用处理该标签，实际运行版本可能与本次拉取不同。如需固定版本，请修改 compose 的 image 字段或设置 NB_IMAGE。"
      fi
    fi
  fi

  if (( ${#targets[@]} > 0 )); then
    info "重建服务：${targets[*]}"
    if ! run docker compose -f "$COMPOSE_FILE" up -d "${targets[@]}"; then
      die "容器重建失败，请查看上方 docker compose 输出（docker compose -f $COMPOSE_FILE logs --tail=200）。"
    fi
  else
    info "未识别到面板相关服务名，整体重建：docker compose up -d"
    if ! run docker compose -f "$COMPOSE_FILE" up -d; then
      die "容器重建失败，请查看上方 docker compose 输出（docker compose -f $COMPOSE_FILE logs --tail=200）。"
    fi
  fi

  if (( DRY_RUN )); then
    say "[dry-run] 跳过健康检查与结果汇总"
    return 0
  fi

  if ! wait_for_http; then
    warn "面板在 ${HEALTH_TIMEOUT} 秒内没有响应。"
    warn "排查命令：docker compose -f $COMPOSE_FILE logs --tail=200"
    die "更新未通过健康检查。"
  fi

  after_id="$(image_id "$image")"
  [[ -n "$after_id" ]] || after_id="(未知)"

  say ""
  info "更新前镜像 ID：$before_id"
  info "更新后镜像 ID：$after_id"
  if [[ "$before_id" == "$after_id" ]]; then
    info "镜像未发生变化（本地已是最新版本）。"
  else
    info "镜像已更新。"
  fi
  say "--- 更新后容器状态 ---"
  docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
if (( DO_BUILD )); then
  info "按 --build 要求走镜像构建模式"
  update_from_image
elif [[ -d ".git" ]]; then
  update_from_git
else
  update_from_image
fi


say ""
info "更新流程结束。"
