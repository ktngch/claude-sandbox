#!/bin/bash
# mode: user — docker のソケット所有者設定とサービス有効化。
# docker 本体 (docker.io / docker-buildx / docker-compose-v2) は 00-system-packages.sh が入れる。
#
# ソケットへのアクセス権は `usermod -aG docker` ではなく docker.socket の SocketUser で与える。
# 補助グループは SSH 認証時に確定し、Lima は SSH 接続を ControlMaster で多重化するため、
# グループ追加は make reprovision 直後のセッションに反映されない (VM 再起動まで permission denied)。
# SocketUser ならソケットの所有者そのものが変わるので、再ログイン待ちが発生しない。
#
# 毎ブート実行される (cloud-init の scripts_per_boot) ので冪等に書く。
set -euo pipefail

OVERRIDE_DIR=/etc/systemd/system/docker.socket.d
OVERRIDE="${OVERRIDE_DIR}/override.conf"

if ! command -v docker >/dev/null 2>&1; then
  echo >&2 "claude-sandbox: docker が見つからない (00-system-packages.sh が先に走っているはず)"
  exit 1
fi

# 1. ソケットの所有者を VM のユーザーにする drop-in。
#    ユーザー名は id -un から取る。Lima の Go テンプレート変数は make reprovision 経路
#    (スクリプトを生で実行する) では展開されないので使わない。
DESIRED=$(
  cat <<EOF
[Socket]
SocketUser=$(id -un)
SocketGroup=docker
SocketMode=0660
EOF
)

# 内容が同じなら書き換えない。毎ブートの daemon-reload とサービス再起動を避けるため。
changed=0
if [ "$(cat "$OVERRIDE" 2>/dev/null || true)" != "$DESIRED" ]; then
  echo "claude-sandbox: writing ${OVERRIDE}"
  sudo install -d -m 0755 "$OVERRIDE_DIR"
  printf '%s\n' "$DESIRED" | sudo tee "$OVERRIDE" >/dev/null
  sudo chmod 0644 "$OVERRIDE"
  changed=1
fi

# 2. drop-in を変えたときは、ソケットを掴んでいる docker.service ごと落としてから読み直す。
if [ "$changed" = 1 ]; then
  sudo systemctl stop docker.service docker.socket || true
  sudo systemctl daemon-reload
fi

if [ "$changed" = 1 ] || ! systemctl is-active --quiet docker.socket; then
  sudo systemctl enable --now docker.socket docker.service
fi

# 3. ソケット経由で疎通するまで待つ (このユーザーで docker info が通ることの確認も兼ねる)
if ! timeout 60s bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'; then
  echo >&2 "claude-sandbox: docker daemon に繋がらない。sudo journalctl -u docker.service を確認してください"
  exit 1
fi

echo "claude-sandbox: docker ready ($(docker --version))"
