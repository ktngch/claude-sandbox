#!/bin/bash
# mode: user — 作業ディレクトリと git の初期設定。
# ~/.claude 配下には一切触れない (対話ログインの成果物を壊さないため)。
set -euo pipefail

mkdir -p "${HOME}/workspace"

# git 設定は未設定のキーだけ書き込む。ユーザーが VM 内で変更した値を上書きしない。
git_default() {
  local key="$1" value="$2"
  # 空値、および未展開の Lima テンプレート変数は無視する。
  # ここに "{" を 2 個続けて書くと Lima 側の Go テンプレート解析が壊れるので 1 個で判定する。
  case "$value" in
    ""|*"{"*) return 0 ;;
  esac
  if ! git config --global --get "$key" >/dev/null 2>&1; then
    git config --global "$key" "$value"
    echo "sandbox-vm: git config --global ${key} = ${value}"
  fi
}

git_default init.defaultBranch main
git_default user.name  '{{.Param.gitUserName}}'
git_default user.email '{{.Param.gitUserEmail}}'

echo "sandbox-vm: dev env ready (workspace: ${HOME}/workspace)"
