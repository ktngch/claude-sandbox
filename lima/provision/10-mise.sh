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

# mise 本体のバージョンは固定する (暫定)。
#
# 2026.8.4 の aqua backend に regression があり、claude (aqua:anthropics/claude-code) が
#   Failed to install aqua:anthropics/claude-code@latest: relative URL without a base
# で落ちる。aqua registry 側は version_overrides でベースの type: http から
# type: github_release に切り替える構造になっており、2026.8.4 は override 側の
# type / asset を適用できず URL を空のまま組み立てている (実測: 2.1.126 は入るが 2.1.227 は落ちる)。
#
# これを踏むと mise install が非ゼロで終わってこのスクリプトが set -e で死ぬ。
# Lima は provision の失敗を WARNING だけで流すので後続は動き、claude の shim だけが
# 存在しない VM ができる。その結果 claude-sandbox.yaml の readiness probe が
# 900 秒待ってから失敗し、make up がタイムアウトまで待たされた末に落ちる。
#
# 上流が直ったらこのピンを外して latest 追随に戻すこと:
#   https://github.com/jdx/mise/pull/11804
MISE_VERSION_PIN=v2026.7.18

# 1. mise 本体 — ピンと違うバージョンのときだけ取得する。
#    「未導入のときだけ」にすると、既に壊れたバージョンが入っている VM を
#    make reprovision で直せない。`mise --version` の出力は
#    "2026.7.18 linux-arm64 (2026-07-30)" の形なので先頭フィールドだけ見る。
#    stderr を捨てているのは、ピンが上流より古い間ずっと自己更新の警告が出るため。
CURRENT_MISE=""
if [ -x "$MISE_BIN" ]; then
  CURRENT_MISE=$("$MISE_BIN" --version 2>/dev/null | awk '{print $1}')
fi

if [ "$CURRENT_MISE" != "${MISE_VERSION_PIN#v}" ]; then
  echo "claude-sandbox: installing mise ${MISE_VERSION_PIN} (current: ${CURRENT_MISE:-none})"
  curl -fsSL https://mise.run | MISE_VERSION="$MISE_VERSION_PIN" sh
else
  echo "claude-sandbox: mise already at ${CURRENT_MISE}"
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
