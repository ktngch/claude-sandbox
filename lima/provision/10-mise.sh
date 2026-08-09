#!/bin/bash
# mode: user — mise 本体の導入、シェル統合、mise.toml に書かれたツールのインストール。
# 毎ブート実行されるので各操作をそれぞれ個別にガードする。
set -euo pipefail

MISE_BIN="${HOME}/.local/bin/mise"
MISE_CONFIG="${HOME}/.config/mise/config.toml"
MISE_SHIMS="${HOME}/.local/share/mise/shims"
MARKER='# >>> claude-sandbox mise >>>'
END_MARKER='# <<< claude-sandbox mise <<<'

# 1. mise 本体 — 未導入のときだけ取得する
if [ ! -x "$MISE_BIN" ]; then
  echo "claude-sandbox: installing mise"
  curl -fsSL https://mise.run | sh
else
  echo "claude-sandbox: mise already found ($("$MISE_BIN" --version))"
fi

# 05-zsh.sh / 40-aws-vault.sh と同じく、マーカーの有無ではなく中身を比較する。
# 存在チェックだけだと、後からこのブロックを直したときに既存 VM へ伝播しない。
# 削除してから末尾に追記し直すので、05-zsh.sh が書いた土台より後ろの位置は保たれる。
write_block() {
  local file="$1" desired="$2" current
  touch "$file"
  current=$(sed -n "/^${MARKER}\$/,/^${END_MARKER}\$/p" "$file")
  if [ "$current" != "$desired" ]; then
    echo "claude-sandbox: writing the mise block to ${file}"
    if [ -n "$current" ]; then
      sed -i "/^${MARKER}\$/,/^${END_MARKER}\$/d" "$file"
    fi
    printf '\n%s\n' "$desired" >>"$file"
  fi
}

# 2a. ~/.zprofile に PATH を通す。
#     zsh は ~/.zshrc を対話シェルでしか読まないので、`zsh -lc cmd` のような非対話実行に
#     効くのはこちら。shims 経由なので activate 無しでもツールが引ける。
#     ~/.zshenv ではなく ~/.zprofile なのは CLAUDE.md 不変条件 #4 を参照。
write_block "${HOME}/.zprofile" "$(
  cat <<EOF
${MARKER}
export PATH="\${HOME}/.local/bin:${MISE_SHIMS}:\${PATH}"
${END_MARKER}
EOF
)"

# 2b. 対話シェルでは activate を使う (ディレクトリごとの env 切り替えが効く)
write_block "${HOME}/.zshrc" "$(
  cat <<EOF
${MARKER}
export PATH="\${HOME}/.local/bin:\${PATH}"
eval "\$(mise activate zsh)"
${END_MARKER}
EOF
)"

# 3. ツール本体 — mise install はインストール済みバージョンをスキップするため本質的に冪等。
#    ここにスタンプは置かない。置いてしまうと "latest" 指定のツール (claude 等) が
#    上流の更新に追随できなくなる。
if [ ! -f "$MISE_CONFIG" ]; then
  echo >&2 "claude-sandbox: ${MISE_CONFIG} が無い (provision の mode: data が先に走っているはず)"
  exit 1
fi

"$MISE_BIN" trust --yes "$MISE_CONFIG"
"$MISE_BIN" install --yes
"$MISE_BIN" reshim

echo "claude-sandbox: mise tools ready"
"$MISE_BIN" ls --installed
