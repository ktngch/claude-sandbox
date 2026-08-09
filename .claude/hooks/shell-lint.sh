#!/bin/bash
# PostToolUse (Write|Edit) — provision の *.sh を触ったら shellcheck + 構文チェック。
# provision スクリプトは VM 内で root / 毎ブート走るので、静的解析の価値が高い。
set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')
case "$file" in *.sh) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

problems=""
syn=$(bash -n "$file" 2>&1)       || problems+="bash -n が失敗しました:\n${syn}\n"
if command -v shellcheck >/dev/null 2>&1; then
  sc=$(shellcheck "$file" 2>&1)   || problems+="shellcheck の指摘:\n${sc}\n"
fi

if [ -n "$problems" ]; then
  printf 'claude-sandbox harness guard (%s):\n%b' "$(basename "$file")" "$problems" >&2
  exit 2
fi
exit 0
