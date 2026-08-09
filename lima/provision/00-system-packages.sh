#!/bin/bash
# mode: system (root) — Lima の provision スクリプトは cloud-init の scripts_per_boot
# として毎回のブートで実行される。パッケージリストのハッシュをスタンプ名に埋め込み、
# リストを変更したときだけ再実行されるようにする。
set -euo pipefail

# mise が扱わない土台のみをここで入れる。ランタイム類は mise.toml 側の担当。
PACKAGES=(
  ca-certificates
  curl
  git
  unzip
  xz-utils
  build-essential
  pkg-config
  # VM のログインシェル。mise registry に zsh は無いので apt 側の担当。
  # rc ファイルの配線と chsh は 05-zsh.sh が行う。
  zsh
  # docker はデーモン + systemd 管理なので mise では扱えない。apt 側の担当。
  # ソケットの所有者設定とサービス有効化は 30-docker.sh が行う。
  docker.io
  docker-buildx
  docker-compose-v2
)

STAMP_DIR=/var/lib/claude-sandbox
STAMP="${STAMP_DIR}/apt.$(printf '%s\n' "${PACKAGES[@]}" | sha256sum | cut -c1-16)"

if [ -f "$STAMP" ]; then
  echo "claude-sandbox: system packages already installed (${STAMP}); skipping apt"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${PACKAGES[@]}"

install -d "$STAMP_DIR"
touch "$STAMP"
echo "claude-sandbox: system packages installed"
