#!/bin/bash
# PostToolUse (Write|Edit) — provision の *.sh を触ったら shellcheck + 構文チェック。
# provision スクリプトは VM 内で root / 毎ブート走るので、静的解析の価値が高い。
set -uo pipefail

# hook は shellcheck を -x 無しで走らせるので、source=/dev/null で SC1091 を抑える。
# (これが無いと shell-lint.sh 自身が自分と workflow-lint.sh を落とす)
# shellcheck source=/dev/null
. "$(dirname "$0")/_common.sh"

hook_read_payload
file=$(hook_target_file)
case "$file" in *.sh) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

run_check 'bash -n が失敗しました' bash -n "$file"
run_check 'shellcheck の指摘' shellcheck "$file"

report "$(basename "$file")"
