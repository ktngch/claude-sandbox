#!/bin/bash
# mode: user — sheldon (zsh プラグインマネージャ) のシェル統合とプラグインの取得。
# sheldon 本体は mise.vm.toml、プラグインの定義は sheldon.plugins.toml の担当。
#
# 書き込み先は ~/.zprofile ではなく ~/.zshrc 側の断片ディレクトリ
# (CLAUDE.md 不変条件 #4 の例外)。autosuggestions も syntax-highlighting も
# ZLE ウィジェットなので、対話シェルにしか意味が無い。
#
# 断片の番号 (60) が最大なのは、ローダが番号順に source するため。
# zsh-syntax-highlighting は upstream が "must be the last plugin sourced" と明記して
# おり、starship init zsh が定義する ZLE ウィジェットより後で source される必要がある。
# ~/.config/claude-sandbox/zshrc.d/ の中で末尾のままにしておくこと。
set -euo pipefail

FRAGMENT="${HOME}/.config/claude-sandbox/zshrc.d/60-sheldon.zsh"
install -d -m 0755 "$(dirname "$FRAGMENT")"
cat >"$FRAGMENT" <<'EOF'
# sheldon は mise 管理。未インストールでも対話シェルが壊れないようガードする。
if command -v sheldon >/dev/null 2>&1; then
  eval "$(sheldon source)"
fi
EOF
chmod 0644 "$FRAGMENT"

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
