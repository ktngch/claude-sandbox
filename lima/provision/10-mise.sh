#!/bin/bash
# mode: user — mise 本体の導入、シェル統合、mise.toml に書かれたツールのインストール。
# 毎ブート実行されるので各操作をそれぞれ個別にガードする。
set -euo pipefail

MISE_BIN="${HOME}/.local/bin/mise"
MISE_CONFIG="${HOME}/.config/mise/config.toml"
MISE_SHIMS="${HOME}/.local/share/mise/shims"
MARKER='# >>> sandbox-vm mise >>>'

# 1. mise 本体 — 未導入のときだけ取得する
if [ ! -x "$MISE_BIN" ]; then
  echo "sandbox-vm: installing mise"
  curl -fsSL https://mise.run | sh
else
  echo "sandbox-vm: mise already found ($("$MISE_BIN" --version))"
fi

# 2a. ~/.profile に PATH を通す。
#     Ubuntu の ~/.bashrc は非対話シェルで冒頭 return するので、`limactl shell ... -- cmd` の
#     ような非対話実行に効くのはこちら。shims 経由なので activate 無しでもツールが引ける。
if ! grep -qF "$MARKER" "${HOME}/.profile" 2>/dev/null; then
  echo "sandbox-vm: adding PATH entries to ~/.profile"
  cat >>"${HOME}/.profile" <<EOF

${MARKER}
export PATH="\${HOME}/.local/bin:${MISE_SHIMS}:\${PATH}"
# <<< sandbox-vm mise <<<
EOF
fi

# 2b. 対話シェルでは activate を使う (ディレクトリごとの env 切り替えが効く)
if ! grep -qF "$MARKER" "${HOME}/.bashrc" 2>/dev/null; then
  echo "sandbox-vm: adding mise activation to ~/.bashrc"
  cat >>"${HOME}/.bashrc" <<EOF

${MARKER}
export PATH="\${HOME}/.local/bin:\${PATH}"
eval "\$(mise activate bash)"
# <<< sandbox-vm mise <<<
EOF
fi

# 3. ツール本体 — mise install はインストール済みバージョンをスキップするため本質的に冪等。
#    ここにスタンプは置かない。置いてしまうと "latest" 指定のツール (claude 等) が
#    上流の更新に追随できなくなる。
if [ ! -f "$MISE_CONFIG" ]; then
  echo >&2 "sandbox-vm: ${MISE_CONFIG} が無い (provision の mode: data が先に走っているはず)"
  exit 1
fi

"$MISE_BIN" trust --yes "$MISE_CONFIG"
"$MISE_BIN" install --yes
"$MISE_BIN" reshim

echo "sandbox-vm: mise tools ready"
"$MISE_BIN" ls --installed
