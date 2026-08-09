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
)

STAMP_DIR=/var/lib/sandbox-vm
STAMP="${STAMP_DIR}/apt.$(printf '%s\n' "${PACKAGES[@]}" | sha256sum | cut -c1-16)"

if [ -f "$STAMP" ]; then
  echo "sandbox-vm: system packages already installed (${STAMP}); skipping apt"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${PACKAGES[@]}"

install -d "$STAMP_DIR"
touch "$STAMP"
echo "sandbox-vm: system packages installed"
