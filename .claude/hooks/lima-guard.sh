#!/bin/bash
# PostToolUse (Write|Edit) — lima/ 配下を触ったときだけ走る。
#
#   1. limactl validate の *警告* を失敗として扱う (CLAUDE.md 不変条件 #3)。
#      limactl は provision スクリプトの Go テンプレート解析に失敗しても warning を
#      出すだけで "OK" / exit 0 を返すので、make validate だけでは検知できない。
#   2. 隔離モデル (不変条件 #1) が yaml から抜けていないかを確認する。
set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')
[ -n "$file" ] || exit 0

root=$(cd "$(dirname "$file")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
case "$file" in "$root"/lima/*) ;; *) exit 0 ;; esac

yaml="$root/lima/claude-code.yaml"
[ -f "$yaml" ] || exit 0
problems=""

if ! out=$(limactl validate "$yaml" 2>&1); then
  problems+="limactl validate が失敗しました:\n$(printf '%s' "$out" | tail -5)\n"
elif printf '%s' "$out" | grep -q 'level=warning'; then
  problems+="limactl validate が警告を出しました (exit 0 なので make validate では素通りします)。\n"
  # 原因の大半は provision スクリプト内の連続した '{{' (不変条件 #3)。該当ファイルを名指しする。
  hits=$(grep -ln '{{' "$root"/lima/provision/*.sh 2>/dev/null)
  if [ -n "$hits" ]; then
    problems+="連続した '{{' を含む provision スクリプト (不変条件 #3):\n$(printf '%s' "$hits" | sed 's|^|  |')\n"
  fi
  problems+="詳細: $(printf '%s' "$out" | grep -o 'error=.*' | head -1)\n"
fi

grep -qE '^mounts: \[\]' "$yaml"                || problems+="lima/claude-code.yaml の 'mounts: []' が失われています (不変条件 #1)。\n"
grep -qE '^\s*loadDotSSHPubKeys: false' "$yaml" || problems+="ssh.loadDotSSHPubKeys が false ではありません (不変条件 #1)。\n"
grep -qE '^\s*forwardAgent: false' "$yaml"      || problems+="ssh.forwardAgent が false ではありません (不変条件 #1)。\n"
! grep -q 'template:_default/mounts' "$yaml"    || problems+="base に template:_default/mounts が入っています (ホームが RO マウントされます)。\n"

if [ -n "$problems" ]; then
  printf 'sandbox-vm harness guard:\n%b' "$problems" >&2
  exit 2
fi
exit 0
