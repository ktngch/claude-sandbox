#!/bin/bash
# PostToolUse (Write|Edit) — .github/workflows/ の yaml を触ったら actionlint + zizmor。
# CI (.github/workflows/actions-lint.yml) と同じ検査を編集時にも回す。
#
# zizmor は --offline で走らせる。編集のたびにネットワークと GitHub トークンに
# 依存させないため。オフラインだと known-vulnerable-actions 等は落ちるが、
# unpinned-uses や artipacked はオフラインでも効く (それらは CI で改めて全部回る)。
set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')
case "$file" in */.github/workflows/*.yml | */.github/workflows/*.yaml) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

problems=""
if command -v actionlint >/dev/null 2>&1; then
  al=$(actionlint "$file" 2>&1)          || problems+="actionlint の指摘:\n${al}\n"
fi
if command -v zizmor >/dev/null 2>&1; then
  zz=$(zizmor --offline "$file" 2>&1)    || problems+="zizmor の指摘:\n${zz}\n"
fi

if [ -n "$problems" ]; then
  printf 'sandbox-vm harness guard (%s):\n%b' "$(basename "$file")" "$problems" >&2
  exit 2
fi
exit 0
