#!/bin/bash
# mode: user — starship のシェル統合。starship 本体は mise.toml の担当。
#
# 設定ファイル (~/.config/starship.toml) は置かない。既定のプリセットをそのまま使う。
#
# 書き込み先は ~/.zprofile ではなく ~/.zshrc 側の断片ディレクトリ
# (CLAUDE.md 不変条件 #4 の例外)。プロンプトは対話シェルにしか意味が無いため。
# `zsh -lc cmd` のような非対話実行では zsh が .zshrc を読まないので、そちらには影響しない。
#
# 番号 (50) がそのまま source 順になる。10-mise.sh の断片より後ろなので、
# mise が PATH に通した starship を下の command -v が拾える。
set -euo pipefail

FRAGMENT="${HOME}/.config/claude-sandbox/zshrc.d/50-starship.zsh"
install -d -m 0755 "$(dirname "$FRAGMENT")"
cat >"$FRAGMENT" <<'EOF'
# starship は mise 管理。未インストールでも対話シェルが壊れないようガードする。
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
EOF
chmod 0644 "$FRAGMENT"

echo "claude-sandbox: starship prompt wired into ~/.zshrc"
