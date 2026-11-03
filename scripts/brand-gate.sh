#!/usr/bin/env bash
# 品牌门禁：拦住上游标识回流到「用户可见文案」。
#
# 契约分三层（见 decisions.md 决策 2）：
#   1. 部署契约 —— artisan 命令名 xboard:install/update/statistics/rollback、
#      xboard-node 二进制名：对外承诺，不在检查范围。
#   2. 功能性标识 —— 编译产物里的 PANEL_TYPE:"Xboard"、CSS 类名 v2board-no-access、
#      旧语言包兼容替换 "V2Board Admin"：改动会破坏主题或兼容性，不在检查范围。
#      这类只出现在 public/assets 与 theme 的 *-generated 产物中。
#   3. 用户可见文案 —— 语言包 JSON 值、README 正文、主题 index/dashboard 模板：
#      **必须**为自有品牌。本门禁只查这一层。
#
# 退出码：0 通过，1 发现上游标识。

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

violations=0
report=""

# --- 第一类：语言包里的「值」（引号内文本），键名与变量名不算 ---
for f in public/assets/admin/locales/*.js lang/*.php; do
  [ -f "$f" ] || continue
  hits=$(grep -oE '"[^"]+":\s*"[^"]*"' "$f" 2>/dev/null \
    | grep -iE 'cedar2025|xboard|v2board' \
    | grep -vE 'xboard-node|xboard:(install|update|statistics|rollback)' \
    | sed "s|^|$f: |" || true)
  if [ -n "$hits" ]; then
    violations=$((violations + $(printf '%s\n' "$hits" | wc -l)))
    report+="$hits"$'\n'
  fi
done

# --- 第二类：README 与主题模板正文 ---
for f in README.md theme/Nboard/index.html theme/Nboard/dashboard.blade.php; do
  [ -f "$f" ] || continue
  hits=$(grep -InE 'cedar2025|xboard|Xboard|v2board|V2Board' "$f" 2>/dev/null \
    | grep -vE 'xboard-node|xboard:(install|update|statistics|rollback)|XboardUpdate|XboardInstall|XboardRollback|XboardStatistics' \
    | sed "s|^|$f:|" || true)
  if [ -n "$hits" ]; then
    violations=$((violations + $(printf '%s\n' "$hits" | wc -l)))
    report+="$hits"$'\n'
  fi
done

if [ "$violations" -gt 0 ]; then
  echo "品牌门禁失败：用户可见面发现 $violations 处上游标识"
  echo "-----------------------------------------------------------"
  printf '%s' "$report" | head -40
  echo "-----------------------------------------------------------"
  echo "部署契约（artisan 命令名 / xboard-node）与功能性标识（PANEL_TYPE、CSS 类名）不在此列。"
  exit 1
fi

echo "品牌门禁通过：用户可见面无上游标识残留"
exit 0
