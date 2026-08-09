#!/bin/bash
# mode: user — aws-vault のバックエンド設定。aws-vault / awscli 本体は mise.toml の担当。
#
# バックエンドは file (~/.awsvault/keys/ をパスフレーズで暗号化) に固定する。
# Linux の自動選択に任せると keyctl (カーネルキーリング) 等が選ばれて挙動が読みにくくなる。
#
# secret-service (gnome-keyring) も技術的には動くが、デーモン常駐 + ブートごとの
# アンロック手順 + 既定コレクションの手当てが必要で、この VM に見合う複雑さではないため採らない。
#
# パスフレーズは aws-vault が対話で聞く。AWS_VAULT_FILE_PASSPHRASE を provision や
# ホスト側 (Makefile・yaml・~/.lima/<name>/) に書かないこと (GitHub PAT と同じ扱い)。
#
# 毎ブート実行される (cloud-init の scripts_per_boot) ので冪等に書く。
set -euo pipefail

AWS_MARKER='# >>> claude-sandbox aws-vault >>>'
AWS_END_MARKER='# <<< claude-sandbox aws-vault <<<'

# CLAUDE.md 不変条件 #4 の通り .bashrc ではなく .profile に置く
# (非対話の `limactl shell -- cmd` にも効かせるため)。
#
# マーカーの有無ではなく中身を比較する。存在チェックだけだと、後からこのブロックに
# export を足したときに既存 VM へ伝播しない。
DESIRED_BLOCK=$(
  cat <<EOF
${AWS_MARKER}
export AWS_VAULT_BACKEND=file
# パスフレーズ入力を GUI ダイアログに逃がさない (headless なので出しても誰も見られない)
export AWS_VAULT_PROMPT=terminal
${AWS_END_MARKER}
EOF
)

touch "${HOME}/.profile"
CURRENT_BLOCK=$(sed -n "/^${AWS_MARKER}\$/,/^${AWS_END_MARKER}\$/p" "${HOME}/.profile")

if [ "$CURRENT_BLOCK" != "$DESIRED_BLOCK" ]; then
  echo "claude-sandbox: writing the aws-vault block to ~/.profile"
  if [ -n "$CURRENT_BLOCK" ]; then
    sed -i "/^${AWS_MARKER}\$/,/^${AWS_END_MARKER}\$/d" "${HOME}/.profile"
  fi
  printf '\n%s\n' "$DESIRED_BLOCK" >>"${HOME}/.profile"
fi

echo "claude-sandbox: aws-vault backend = file (~/.awsvault/keys/)"
