#!/bin/bash
# mode: user — VM のログインシェルを zsh にする。zsh 本体は 00-system-packages.sh (apt) の担当。
#
# このスクリプトが ~/.zprofile と ~/.zshrc の「本体」を所有する唯一の場所。
# 他の provision スクリプトはこの 2 ファイルに直接書かず、断片ディレクトリ
#   ~/.config/claude-sandbox/zprofile.d/NN-<name>.zsh
#   ~/.config/claude-sandbox/zshrc.d/NN-<name>.zsh
# にファイルを 1 枚置くだけにする。ここで書くローダがそれを番号順に source する。
#
# この方式にしているのは、source される順序をファイル名で決めるため。各スクリプトが
# rc ファイルに直接追記していた頃は「provision の実行順 = rc 内の順序」という
# 暗黙の依存があり、スクリプトをリネームすると静かに壊れた。
# 断片は丸ごと上書きするだけなので、冪等性も構造的に保証される。
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
# 毎ブート実行される (cloud-init の scripts_per_boot) ので冪等に書く。
set -euo pipefail

MARKER='# >>> claude-sandbox zsh >>>'
END_MARKER='# <<< claude-sandbox zsh <<<'
FRAGMENT_ROOT="${HOME}/.config/claude-sandbox"

if ! ZSH_BIN=$(command -v zsh); then
  echo >&2 "claude-sandbox: zsh が見つからない (00-system-packages.sh が先に走っているはず)"
  exit 1
fi

# マーカーの有無ではなく中身を比較する。存在チェックだけだと、後からこのブロックを
# 直したときに既存 VM へ伝播しない。VM 内でユーザーが手で足した内容は壊さないので、
# rc ファイルを丸ごと上書きせずこの方式を使っている。
rc_changed=0

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
    rc_changed=1
  fi
}

# 断片方式へ移行する前の VM には、各スクリプトが直接書いたブロックが残っている。
# ローダが読む断片と二重に効いてしまうので消しておく。
# 移行済みの VM では no-op。十分に行き渡ったら削除してよい。
strip_legacy_block() {
  local file="$1" name="$2"
  [ -f "$file" ] || return 0
  grep -qF "# >>> claude-sandbox ${name} >>>" "$file" || return 0
  echo "claude-sandbox: removing the legacy ${name} block from ${file}"
  sed -i "/^# >>> claude-sandbox ${name} >>>\$/,/^# <<< claude-sandbox ${name} <<<\$/d" "$file"
  rc_changed=1
}

# ブロックの削除は、その前に置かれていた空行を取り残す (write_block も旧ブロック掃除も
# 「消してから \n 付きで追記し直す」ため)。放っておくと書き換えのたびに空行が増える。
# 連続した空行を 1 つに潰し、先頭の空行を落とす。
# 実際に書き換えたときだけ呼ぶ (ユーザーが入れた空行を毎ブート畳まないため)。
tidy_blank_lines() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  tmp=$(mktemp)
  cat -s "$file" | sed '/./,$!d' >"$tmp"
  cmp -s "$file" "$tmp" || cat "$tmp" >"$file"
  rm -f "$tmp"
}

for legacy in mise git aws-vault starship sheldon; do
  strip_legacy_block "${HOME}/.zprofile" "$legacy"
  strip_legacy_block "${HOME}/.zshrc" "$legacy"
done

install -d -m 0755 "${FRAGMENT_ROOT}/zprofile.d" "${FRAGMENT_ROOT}/zshrc.d"

# 1. ~/.zprofile の土台とローダ。
#    このファイルはログインのたびに走り、断片が PATH を prepend するので、
#    typeset -U で重複を潰しておく。以降の PATH 代入にも継続して効く。
#    glob 修飾子 (N) は NULL_GLOB。断片が 1 つも無くてもエラーにならない。
write_block "${HOME}/.zprofile" "$(
  cat <<EOF
${MARKER}
typeset -U path PATH
for _f in "\${HOME}"/.config/claude-sandbox/zprofile.d/*.zsh(N); do
  source "\$_f"
done
unset _f
${END_MARKER}
EOF
)"

# 2. ~/.zshrc の土台とローダ。
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
for _f in "\${HOME}"/.config/claude-sandbox/zshrc.d/*.zsh(N); do
  source "\$_f"
done
unset _f
${END_MARKER}
EOF
)"

# 3. 書き換えで生じた余分な空行を畳む。rc ファイルへの書き込みが全部済んでから。
if [ "$rc_changed" = 1 ]; then
  tidy_blank_lines "${HOME}/.zprofile"
  tidy_blank_lines "${HOME}/.zshrc"
fi

# 4. ログインシェルの切り替え。rc ファイルを書いた後に行う。
#    どちらも存在しない状態で対話 zsh が起動すると zsh-newuser-install のウィザードが出る。
USER_NAME=$(id -un)
CURRENT_SHELL=$(getent passwd "$USER_NAME" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "$ZSH_BIN" ]; then
  echo "claude-sandbox: changing login shell ${CURRENT_SHELL} -> ${ZSH_BIN}"
  sudo chsh -s "$ZSH_BIN" "$USER_NAME"
fi

echo "claude-sandbox: login shell = ${ZSH_BIN} (fragments: ${FRAGMENT_ROOT})"
