#!/bin/bash
# mode: user — sheldon (zsh プラグインマネージャ) のシェル統合とプラグインの取得。
# sheldon 本体は mise.vm.toml、プラグインの定義は sheldon.plugins.toml の担当。
#
# 書き込み先は ~/.zprofile ではなく ~/.zshrc (CLAUDE.md 不変条件 #4 の例外)。
# autosuggestions も syntax-highlighting も ZLE ウィジェットなので、対話シェルにしか
# 意味が無い。`zsh -lc cmd` のような非対話実行では zsh が .zshrc を読まない。
#
# 番号が 50-starship.sh より大きいのは、ブロックが .zshrc の末尾に来るようにするため。
# zsh-syntax-highlighting は upstream が "must be the last plugin sourced" と明記して
# おり、starship init zsh が定義する ZLE ウィジェットより後で source される必要がある。
# 各スクリプトはブロックを削除してから末尾に追記し直すので、番号順 = .zshrc 内の順序。
#
# 毎ブート実行される (cloud-init の scripts_per_boot) ので冪等に書く。
set -euo pipefail

SHELDON_MARKER='# >>> claude-sandbox sheldon >>>'
SHELDON_END_MARKER='# <<< claude-sandbox sheldon <<<'

# 40-aws-vault.sh / 50-starship.sh と同じく、マーカーの有無ではなく中身を比較する。
# 存在チェックだけだと、後からこのブロックを直したときに既存 VM へ伝播しない。
DESIRED_BLOCK=$(
  cat <<EOF
${SHELDON_MARKER}
# sheldon は mise 管理。未インストールでも対話シェルが壊れないようガードする。
if command -v sheldon >/dev/null 2>&1; then
  eval "\$(sheldon source)"
fi
${SHELDON_END_MARKER}
EOF
)

touch "${HOME}/.zshrc"
CURRENT_BLOCK=$(sed -n "/^${SHELDON_MARKER}\$/,/^${SHELDON_END_MARKER}\$/p" "${HOME}/.zshrc")

if [ "$CURRENT_BLOCK" != "$DESIRED_BLOCK" ]; then
  echo "claude-sandbox: writing the sheldon block to ~/.zshrc"
  if [ -n "$CURRENT_BLOCK" ]; then
    sed -i "/^${SHELDON_MARKER}\$/,/^${SHELDON_END_MARKER}\$/d" "${HOME}/.zshrc"
  fi
  printf '\n%s\n' "$DESIRED_BLOCK" >>"${HOME}/.zshrc"
fi

# プラグインをここで先に clone しておく。対話ログインまで持ち越すと、初回の
# `sheldon source` が clone の進捗を出して .zshrc が「何も出力しない」を破る。
#
# `sheldon lock` は clone 済みのソースをスキップする (更新は --update のときだけ) ので
# 本質的に冪等。10-mise.sh の `mise install` と同じ理由でスタンプは置かない。
if command -v sheldon >/dev/null 2>&1; then
  sheldon lock
else
  echo >&2 "claude-sandbox: sheldon が見つからない (10-mise.sh が先に走っているはず)"
fi

echo "claude-sandbox: sheldon wired into ~/.zshrc"
