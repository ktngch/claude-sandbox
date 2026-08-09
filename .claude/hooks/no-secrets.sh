#!/bin/bash
# PreToolUse (Write|Edit) — ホスト側のファイルに実クレデンシャルを書き込ませない。
#
# CLAUDE.md 不変条件 #1: GitHub PAT と AWS_VAULT_FILE_PASSPHRASE はユーザーが VM 内で
# export するものであり、ホスト側 (Makefile・yaml・provision・~/.lima/) には書かない。
# README / provision は export 行を「書き方」として例示するので、
# 変数名への言及やプレースホルダ (github_pat_... 等) は通し、実値だけを弾く。
set -uo pipefail

payload=$(cat)
body=$(printf '%s' "$payload" | jq -r '[.tool_input.content?, .tool_input.new_string?] | map(select(. != null)) | join("\n")')
[ -n "$body" ] || exit 0

hits=""
# 1. トークン / キーそのものの形をしたもの
printf '%s' "$body" | grep -qE 'github_pat_[A-Za-z0-9_]{22,}' && hits+="GitHub fine-grained PAT らしき文字列; "
printf '%s' "$body" | grep -qE 'gh[pousr]_[A-Za-z0-9]{30,}'   && hits+="GitHub classic token らしき文字列; "
printf '%s' "$body" | grep -qE 'AKIA[0-9A-Z]{16}'             && hits+="AWS アクセスキー ID らしき文字列; "

# 2. 秘密の環境変数への「実値」代入。
#    除外: 変数参照 ($VAR / ${VAR})、空値、プレースホルダ (... / <foo> / xxxx / your- 等)。
assigns=$(printf '%s' "$body" \
  | grep -oE '(AWS_VAULT_FILE_PASSPHRASE|AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|GH_TOKEN)[[:space:]]*=[^[:space:]#]*' \
  | grep -vE '=[[:space:]]*["'"'"']?(\$|$)' \
  | grep -vE '(\.\.\.|<[^>]*>|[Xx]{3,}|[Yy]our|EXAMPLE|example|dummy|CHANGEME|REPLACE|TODO)' \
  | grep -E '=["'"'"']?[A-Za-z0-9/+_-]{8,}')
[ -n "$assigns" ] && hits+="秘密の環境変数への実値代入 ($(printf '%s' "$assigns" | head -1 | cut -c1-40)...); "

if [ -n "$hits" ]; then
  jq -n --arg r "claude-sandbox harness guard: ${hits}CLAUDE.md 不変条件 #1 により、PAT / AWS パスフレーズはホスト側 (Makefile・yaml・provision・~/.lima/) に書けません。ユーザーが VM 内で export する経路だけを使ってください。" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0
