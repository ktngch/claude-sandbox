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
# 書き込み先は 05-zsh.sh が用意した ~/.zprofile 側の断片ディレクトリ。
# .zshrc ではなく .zprofile なのは CLAUDE.md 不変条件 #4 の通り
# (非対話の `limactl shell -- cmd` にも効かせるため)。
set -euo pipefail

FRAGMENT="${HOME}/.config/claude-sandbox/zprofile.d/40-aws-vault.zsh"
install -d -m 0755 "$(dirname "$FRAGMENT")"
cat >"$FRAGMENT" <<'EOF'
export AWS_VAULT_BACKEND=file
# パスフレーズ入力を GUI ダイアログに逃がさない (headless なので出しても誰も見られない)
export AWS_VAULT_PROMPT=terminal
EOF
chmod 0644 "$FRAGMENT"

echo "claude-sandbox: aws-vault backend = file (~/.awsvault/keys/)"
