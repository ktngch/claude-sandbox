#!/bin/bash
# mode: user — VM のログインシェルを zsh にする。zsh 本体は 00-system-packages.sh (apt) の担当。
#
# ここでは rc ファイルの「土台」だけを作り、最後に chsh でログインシェルを差し替える。
# mise / starship の配線は 10-mise.sh と 50-starship.sh が同じファイルに追記する。
#
# 書き分け (CLAUDE.md 不変条件 #4):
#   ~/.zprofile ... env と PATH。`zsh -lc cmd` のような非対話ログインシェルにも効く。
#   ~/.zshrc    ... 対話シェルにしか意味の無いもの。非対話では読まれない。
#
# ~/.zshenv には書かないこと。zsh の読み込み順は
#   /etc/zshenv -> ~/.zshenv -> /etc/zprofile -> ~/.zprofile -> (対話のみ) ~/.zshrc
# で、Ubuntu の zsh-common が置く /etc/zprofile が /etc/profile を source し、
# そこで PATH が無条件に上書きされる。~/.zshenv に書いた PATH はそこで消える。
#
# このスクリプトの実行順が 10-mise.sh より前なのは、土台のブロックを rc ファイルの
# 先頭に置くため。ブロックは削除してから末尾に追記し直すので、
# 土台 -> mise -> starship の順序が毎ブート保たれる。
#
# 毎ブート実行される (cloud-init の scripts_per_boot) ので冪等に書く。
set -euo pipefail

MARKER='# >>> claude-sandbox zsh >>>'
END_MARKER='# <<< claude-sandbox zsh <<<'

if ! ZSH_BIN=$(command -v zsh); then
  echo >&2 "claude-sandbox: zsh が見つからない (00-system-packages.sh が先に走っているはず)"
  exit 1
fi

# 40-aws-vault.sh / 50-starship.sh と同じく、マーカーの有無ではなく中身を比較する。
# 存在チェックだけだと、後からこのブロックを直したときに既存 VM へ伝播しない。
write_block() {
  local file="$1" desired="$2" current
  touch "$file"
  current=$(sed -n "/^${MARKER}\$/,/^${END_MARKER}\$/p" "$file")
  if [ "$current" != "$desired" ]; then
    echo "claude-sandbox: writing the zsh block to ${file}"
    if [ -n "$current" ]; then
      sed -i "/^${MARKER}\$/,/^${END_MARKER}\$/d" "$file"
    fi
    printf '\n%s\n' "$desired" >>"$file"
  fi
}

# 1. ~/.zprofile の土台。
#    このファイルはログインのたびに走り、後続のブロックが PATH を prepend するので、
#    typeset -U で重複を潰しておく。以降の PATH 代入にも継続して効く。
write_block "${HOME}/.zprofile" "$(
  cat <<EOF
${MARKER}
typeset -U path PATH
${END_MARKER}
EOF
)"

# 2. ~/.zshrc の土台。
#    zsh は既定で履歴ファイルを持たず補完も有効でないため、ここを入れないと
#    Ubuntu の素の bash より対話の体感が劣化する。
#    非対話でも source されうる (Claude Code のシェルスナップショット) ので何も出力しない。
write_block "${HOME}/.zshrc" "$(
  cat <<EOF
${MARKER}
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
# -u は insecure directories の対話プロンプトを抑える。出るとログインが止まってしまう。
autoload -Uz compinit && compinit -u
bindkey -e
${END_MARKER}
EOF
)"

# 3. ログインシェルの切り替え。rc ファイルを書いた後に行う。
#    どちらも存在しない状態で対話 zsh が起動すると zsh-newuser-install のウィザードが出る。
USER_NAME=$(id -un)
CURRENT_SHELL=$(getent passwd "$USER_NAME" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "$ZSH_BIN" ]; then
  echo "claude-sandbox: changing login shell ${CURRENT_SHELL} -> ${ZSH_BIN}"
  sudo chsh -s "$ZSH_BIN" "$USER_NAME"
fi

echo "claude-sandbox: login shell = ${ZSH_BIN}"
