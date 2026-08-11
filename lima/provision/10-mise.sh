#!/bin/bash
# mode: user — mise 本体の導入、シェル統合、mise.toml に書かれたツールのインストール。
# 毎ブート実行されるので各操作をそれぞれ個別にガードする。
#
# シェル統合は ~/.zprofile / ~/.zshrc に直接書かず、05-zsh.sh が用意した
# 断片ディレクトリにファイルを置く。番号 (10) がそのまま source 順になる。
set -euo pipefail

MISE_BIN="${HOME}/.local/bin/mise"
MISE_CONFIG="${HOME}/.config/mise/config.toml"
FRAGMENT_ROOT="${HOME}/.config/claude-sandbox"

# 1. mise 本体 — 未導入のときだけ取得する
if [ ! -x "$MISE_BIN" ]; then
  echo "claude-sandbox: installing mise"
  curl -fsSL https://mise.run | sh
else
  echo "claude-sandbox: mise already found ($("$MISE_BIN" --version))"
fi

# 2a. ~/.zprofile 側に PATH を通す。
#     zsh は ~/.zshrc を対話シェルでしか読まないので、`zsh -lc cmd` のような非対話実行に
#     効くのはこちら。shims 経由なので activate 無しでもツールが引ける。
#     ~/.zshenv ではなく ~/.zprofile なのは CLAUDE.md 不変条件 #4 を参照。
FRAGMENT="${FRAGMENT_ROOT}/zprofile.d/10-mise.zsh"
install -d -m 0755 "$(dirname "$FRAGMENT")"
cat >"$FRAGMENT" <<'EOF'
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}"
EOF
chmod 0644 "$FRAGMENT"

# 2b. 対話シェルでは activate を使う (ディレクトリごとの env 切り替えが効く)
FRAGMENT="${FRAGMENT_ROOT}/zshrc.d/10-mise.zsh"
install -d -m 0755 "$(dirname "$FRAGMENT")"
cat >"$FRAGMENT" <<'EOF'
export PATH="${HOME}/.local/bin:${PATH}"
eval "$(mise activate zsh)"
EOF
chmod 0644 "$FRAGMENT"

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
