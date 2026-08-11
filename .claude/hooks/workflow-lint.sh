#!/bin/bash
# PostToolUse (Write|Edit) — .github/workflows/ の yaml を触ったら actionlint + zizmor。
# CI (.github/workflows/actions-lint.yml) と同じ検査を編集時にも回す。
#
# zizmor は --offline で走らせる。編集のたびにネットワークと GitHub トークンに
# 依存させないため。オフラインだと known-vulnerable-actions 等は落ちるが、
# unpinned-uses や artipacked はオフラインでも効く (それらは CI で改めて全部回る)。
set -uo pipefail

# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

hook_read_payload
file=$(hook_target_file)
case "$file" in */.github/workflows/*.yml | */.github/workflows/*.yaml) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

run_check 'actionlint の指摘' actionlint "$file"
run_check 'zizmor の指摘' zizmor --offline "$file"

report "$(basename "$file")"
