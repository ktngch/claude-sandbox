#!/bin/bash
# hooks 共通のヘルパ。source されることだけを想定しており、単体では何もしない。
# (先頭が _ なので .claude/settings.json の hooks からは呼ばれない)
#
# 各 hook はこの形になる:
#   . "$(dirname "$0")/_common.sh"
#   hook_read_payload
#   file=$(hook_target_file)
#   ... 絞り込み ...
#   run_check '<ラベル>' <コマンド> <引数...>
#   report "$(basename "$file")"
#
# set -euo pipefail は書かない。読み込み側が set -uo pipefail (-e 無し) で走っており、
# 指摘を集めてからまとめて報告する作りなので、途中の非ゼロ終了で止めてはいけない。

hook_payload=''
problems=''

# hook_read_payload — stdin の JSON ペイロードを読む。1 回だけ呼ぶこと。
hook_read_payload() {
  hook_payload=$(cat)
}

# hook_field <jq 式> — ペイロードから値を取り出す。
# 読み込み側が $hook_payload を直に触ると、代入がこのファイル側にあるせいで
# SC2154 (referenced but not assigned) が出る。必ずこの入り口を経由させること。
# なお行頭の "# shellcheck" はディレクティブとして解釈されるので、
# コメントでルール名に触れるときは行頭に置かないこと。
hook_field() {
  printf '%s' "$hook_payload" | jq -r "$1"
}

# hook_target_file — 対象ファイルのパス。Write と Edit で入り口が違うので両方見る。
# 取れなければ空文字。
hook_target_file() {
  hook_field '.tool_response.filePath // .tool_input.file_path // empty'
}

# run_check <ラベル> <コマンド> [引数...]
# コマンドが PATH に無ければ黙って飛ばす (ホストに未導入でも編集を止めない)。
# 非ゼロで終わったらラベルと出力を problems に足す。
run_check() {
  local label="$1"
  shift
  command -v "$1" >/dev/null 2>&1 || return 0
  local out
  out=$("$@" 2>&1) || problems+="${label}:\n${out}\n"
}

# report [表示名] — problems が空なら exit 0、あれば stderr に出して exit 2。
# exit 2 が Claude Code に「この指摘を読んで直せ」と伝える終了コード。
report() {
  [ -n "$problems" ] || exit 0
  if [ -n "${1:-}" ]; then
    printf 'claude-sandbox harness guard (%s):\n%b' "$1" "$problems" >&2
  else
    printf 'claude-sandbox harness guard:\n%b' "$problems" >&2
  fi
  exit 2
}
