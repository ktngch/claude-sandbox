#!/bin/bash
# mode: user — 作業ディレクトリ / git 設定 / GitHub HTTPS 認証の配線。
# ~/.claude 配下には一切触れない (対話ログインの成果物を壊さないため)。
#
# 毎ブート実行される (cloud-init の scripts_per_boot) ほか、
# Makefile の dev-env ターゲットからも env 付きで直接叩かれる。どちらでも冪等。
set -euo pipefail

GIT_MARKER='# >>> sandbox-vm git >>>'
CREDENTIAL_HELPER="${HOME}/.local/bin/git-credential-github-token"

mkdir -p "${HOME}/workspace"

# 1. git identity — ホストから env で渡された値を正とする (make up / make dev-env)。
#    ブート時の cloud-init 経路では未設定なので何もしない (VM ディスク上の設定が残る)。
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "${GIT_USER_NAME}"
  echo "sandbox-vm: git config --global user.name = ${GIT_USER_NAME}"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "${GIT_USER_EMAIL}"
  echo "sandbox-vm: git config --global user.email = ${GIT_USER_EMAIL}"
fi

# 2. 未設定のときだけ書くもの
if ! git config --global --get init.defaultBranch >/dev/null 2>&1; then
  git config --global init.defaultBranch main
fi

# 3. ghq — clone 先を ~/workspace に固定する (make claude の cd 先と一致させる)
git config --global ghq.root "${HOME}/workspace"

# 4. GitHub の HTTPS 認証。
#    ホストの認証情報を持ち込まない隔離モデルなので、ユーザーが VM 内で
#    export した fine-grained PAT を読むだけの credential helper を置く。
#    トークンはディスクに一切書かれない。
install -d "${HOME}/.local/bin"
cat >"${CREDENTIAL_HELPER}" <<'EOF'
#!/bin/bash
# git credential helper: 環境変数の fine-grained PAT を GitHub の HTTPS 認証に使う。
#   $ export GITHUB_TOKEN=github_pat_...
# get 以外の操作 (store / erase) は保存先が無いので何もしない。
# トークン未設定なら何も返さない → git は認証情報なしとして扱う。
[ "${1:-}" = get ] || exit 0
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
[ -n "$token" ] || exit 0
printf 'username=x-access-token\npassword=%s\n' "$token"
EOF
chmod 0755 "${CREDENTIAL_HELPER}"

# helper の値は絶対パスにする。"/" を含む値を git は実行ファイルのパスとして扱うため、
# PATH に依存せず `limactl shell -- cmd` のような非対話実行でも確実に効く。
git config --global 'credential.https://github.com.helper' "${CREDENTIAL_HELPER}"
git config --global 'credential.https://github.com.username' x-access-token

# 5. ssh 鍵を持ち込まない構成なので、github の ssh URL は https に倒す。
#    多値キーなので --replace-all → --add の順で冪等にする。
git config --global --replace-all url."https://github.com/".insteadOf 'git@github.com:'
git config --global --add url."https://github.com/".insteadOf 'ssh://git@github.com/'

# 6. トークン未設定のまま push すると git がユーザー名入力で待ち続けてしまう。
#    非対話で即エラーにして、エージェントがハングしないようにする。
#    PATH と同じ理由で ~/.bashrc ではなく ~/.profile 側に置く (CLAUDE.md 不変条件 #4)。
if ! grep -qF "$GIT_MARKER" "${HOME}/.profile" 2>/dev/null; then
  echo "sandbox-vm: adding GIT_TERMINAL_PROMPT=0 to ~/.profile"
  cat >>"${HOME}/.profile" <<EOF

${GIT_MARKER}
export GIT_TERMINAL_PROMPT=0
# <<< sandbox-vm git <<<
EOF
fi

echo "sandbox-vm: dev env ready (workspace: ${HOME}/workspace)"
