#!/bin/bash
# mode: user — starship のシェル統合。starship 本体は mise.toml の担当。
#
# 設定ファイル (~/.config/starship.toml) は置かない。既定のプリセットをそのまま使う。
#
# 書き込み先は ~/.profile ではなく ~/.bashrc (CLAUDE.md 不変条件 #4 の例外)。
# プロンプトは対話シェルにしか意味が無いため。`limactl shell -- cmd` のような
# 非対話実行では .bashrc が冒頭 return するので、そちらには影響しない。
#
# 毎ブート実行される (cloud-init の scripts_per_boot) ので冪等に書く。
set -euo pipefail

STARSHIP_MARKER='# >>> sandbox-vm starship >>>'
STARSHIP_END_MARKER='# <<< sandbox-vm starship <<<'

# 40-aws-vault.sh と同じく、マーカーの有無ではなく中身を比較する。
# 存在チェックだけだと、後からこのブロックを直したときに既存 VM へ伝播しない。
DESIRED_BLOCK=$(
  cat <<EOF
${STARSHIP_MARKER}
# starship は mise 管理。未インストールでも対話シェルが壊れないようガードする。
if command -v starship >/dev/null 2>&1; then
  eval "\$(starship init bash)"
fi
${STARSHIP_END_MARKER}
EOF
)

touch "${HOME}/.bashrc"
CURRENT_BLOCK=$(sed -n "/^${STARSHIP_MARKER}\$/,/^${STARSHIP_END_MARKER}\$/p" "${HOME}/.bashrc")

# 10-mise.sh が書く mise ブロック (eval "$(mise activate bash)") より後ろに置く。
# mise activate は評価時点で解決済みの PATH を export するので、この順序なら
# 上の command -v starship が通る。消して末尾に追記し直すので順序は保たれる。
if [ "$CURRENT_BLOCK" != "$DESIRED_BLOCK" ]; then
  echo "sandbox-vm: writing the starship block to ~/.bashrc"
  if [ -n "$CURRENT_BLOCK" ]; then
    sed -i "/^${STARSHIP_MARKER}\$/,/^${STARSHIP_END_MARKER}\$/d" "${HOME}/.bashrc"
  fi
  printf '\n%s\n' "$DESIRED_BLOCK" >>"${HOME}/.bashrc"
fi

echo "sandbox-vm: starship prompt wired into ~/.bashrc"
