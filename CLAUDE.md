# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

macOS 上に Lima で Claude Code 実行用の隔離 VM を立てるための設定リポジトリ。アプリケーションコードは無く、成果物は Lima テンプレート・シェルスクリプト・Makefile のみ。ユーザー向けの説明は `README.md` にある。

## コマンド

```sh
make validate       # Lima テンプレートの検証。YAML やスクリプトを触ったら必ず最初に通す
make up             # 作成 (初回のみ) + 起動 + プロビジョニング
make shell          # VM にログインする (この VM の主目的。claude はログインしてから中で叩く)
make reprovision    # lima/provision/ の変更だけを再適用する
make recreate       # 破棄して作り直す
make status         # 状態確認
make stop           # 停止する (ディスクは残る)
make destroy        # 削除する (VM 内のデータと claude の認証情報も消える)
make ssh-config     # VS Code Remote-SSH 用の Include 行を表示する
make help           # ターゲット一覧
```

`make validate` は `limactl validate` を素で叩くだけなので、**警告が出ても成功する**（不変条件 #3）。合否は編集時の hook と CI が判定する。

hook は「今編集したファイル」にしか走らないので、まとめて直したあとは CI と同じ全数検査をローカルで回す:

```sh
git ls-files -z '*.sh' | xargs -0 -n1 bash -n && git ls-files -z '*.sh' | xargs -0 shellcheck
actionlint -color && GH_TOKEN=$(gh auth token) zizmor .github/workflows && pinact run --check
```

テストフレームワークは無い。検証は実際に VM を起動して確かめる。

## 変更を反映する経路が 2 つある

これを取り違えると「直したのに反映されない」で時間を溶かす。

- **`lima/provision/` を変えた** → `make reprovision`。スクリプトを VM に転送して直接実行するので数十秒で終わる。
- **`lima/claude-sandbox.yaml` を変えた** → `make recreate`。Lima は作成時にテンプレートの内容（provision スクリプトの中身を含む）をインスタンス側 `~/.lima/<name>/lima.yaml` にコピーするため、既存インスタンスに `make up` してもリポジトリ側の yaml 変更は読まれない。

`make reprovision` は yaml の `mode: data` に相当する処理（`mise.vm.toml` → `~/.config/mise/config.toml`、`sheldon.plugins.toml` → `~/.config/sheldon/plugins.toml` の配置）も自前で再現している。yaml 側の provision エントリを増減させたら、Makefile の `reprovision` ターゲットも合わせて更新すること。

`20-dev-env.sh` だけは `dev-env` ターゲットに切り出してあり、`up` と `reprovision` の両方がこれを呼ぶ。ホストの git identity を env で流し込む唯一の経路なので、片方から外さないこと。

### `param:` は使わない

Lima の `param` はインスタンス**作成時**にしか渡せず、既存 VM への `make up`（`limactl start <name>` 経路）では変更できない。さらに `make reprovision` はスクリプトを生のまま実行するので `{{.Param.*}}` が展開されない。ホストから VM に値を渡したいときは、`dev-env` のように `limactl shell -- env KEY=... zsh -lc ...` を使う。

## 不変条件

### 1. 隔離モデルを単独で壊さない

`lima/claude-sandbox.yaml` の `mounts: []`、`ssh.loadDotSSHPubKeys: false`、`ssh.forwardAgent: false` は、VM 内で `claude --dangerously-skip-permissions` を常用できる前提そのもの。マウントや agent forwarding を足すと、VM 内のエージェントがホストの認証情報やソースに到達できるようになる。

`base:` に `template:_default/mounts` を追加してはいけない（ホームが読み取り専用でマウントされる）。他の Lima テンプレートをコピーしてくるときに紛れ込みやすい。

隔離を緩める必要が出たら、`--dangerously-skip-permissions` を付けての常用をやめることとセットで検討する。このフラグを付ける場所は Makefile にも provision にも無く、ユーザーが VM 内で手で打つ。

GitHub への認証は **HTTPS + 環境変数の fine-grained PAT** だけを経路にする。「push できない」を ssh 鍵の配置や `forwardAgent: true` で解決しないこと。トークンはユーザーが VM 内で `export` するものであり、ホスト側（Makefile・yaml・`~/.lima/<name>/`）には一切書かない。

AWS のクレデンシャルは **aws-vault の file バックエンド**だけを経路にする。平文の `~/.aws/credentials` を置かない。パスフレーズ（`AWS_VAULT_FILE_PASSPHRASE`）も PAT と同じ扱いで、ホスト側（Makefile・yaml・`~/.lima/<name>/`）にも provision にも書かない。パスフレーズを `export` した状態ではエージェントも `aws-vault exec` できてしまうので、README には「投入するのは最小権限ロール / 短命クレデンシャルに限る」と明記してある。この非対称性（PAT・AWS だけ穴を開けている）を README の「隔離の境界線」と食い違わせないこと。

### 2. provision スクリプトは毎ブート実行される

Lima の provision は cloud-init の `scripts_per_boot` として登録されるため、VM を再起動するたびに全スクリプトが走る。処理を追加するときは必ずガードを付ける:

- `00-system-packages.sh` — パッケージリストの sha256 をスタンプファイル名に埋め込み、`/var/lib/claude-sandbox/apt.<hash>` があれば `apt-get update` ごとスキップする。リストを変えるとハッシュが変わって自動的に再実行される。
- `05-zsh.sh` — `~/.zprofile` と `~/.zshrc` の**土台**（PATH の重複除去・履歴・補完・キーバインド）を**中身の比較**方式で書き、最後に `chsh` する。`chsh` は `getent passwd` の 7 番目のフィールドと比較して差分があるときだけ。rc ファイルを書いてから `chsh` するのは、`~/.zshrc` などが 1 つも無い状態で対話 zsh が起動すると `zsh-newuser-install` のウィザードが出るため。番号が `10-mise.sh` より小さいのは rc ファイルへの追記順（土台 → mise → starship）を作るためで、この順序に依存があるので入れ替えないこと。`chsh` が効くのは **ssh 経由のログイン**（VS Code Remote-SSH、`ssh lima-<name>`）と VM 内の `$SHELL` だけ。`make shell` は別経路なので不変条件 #5 を参照。

`chsh` の結果は `30-docker.sh` の補助グループと同じく SSH 認証時に確定する。Lima の `ssh.config` は `ControlMaster auto` + `ControlPersist yes` で 1 本の接続を多重化し続け、sshd は認証時にキャッシュした passwd エントリを使い回すため、`make reprovision` 直後のセッションの `$SHELL` は古いままになる。反映させるには接続を張り直す（`limactl shell --reconnect <name>`、`ssh -F ~/.lima/<name>/ssh.config -O exit lima-<name>`、または VM 再起動）。
- `10-mise.sh` — mise 本体は `-x` チェック、シェル統合は `# >>> claude-sandbox mise >>>` マーカーの**中身の比較**で判定。`mise install` は既存バージョンをスキップするので**あえてスタンプを置かない**（置くと `latest` 指定の `claude` が上流更新に追随できなくなる）。
- `20-dev-env.sh` — 書き込みの種類ごとに冪等性の担保が違う。`user.name` / `user.email` は `GIT_USER_NAME` / `GIT_USER_EMAIL` が**非空のときだけ**上書きする（ホスト側を単一の真実にするため。ブート経路では env が空なので VM 内の設定が残る）。`init.defaultBranch` は未設定のときだけ書く。`ghq.root` と credential helper 関連は単一値なので `git config --global` で上書きし続けてよい。`url.insteadOf` は多値キーなので `--replace-all` → `--add` の順で書く（`--add` だけだとブートごとに増殖する）。`~/.zprofile` への `GIT_TERMINAL_PROMPT=0` は `# >>> claude-sandbox git >>>` マーカーの `grep -qF` で判定する。`~/.claude` には触れない（対話ログインの成果物が消えるため）。
- `30-docker.sh` — `docker.socket` の drop-in は**内容を比較して差分があるときだけ**書き、書き換えたときだけ `daemon-reload` とサービス再起動を行う（毎ブート restart するとブートが遅くなる）。ソケットの権限は `usermod -aG docker` ではなく `SocketUser` で与える。補助グループは SSH 認証時に確定し、Lima は SSH 接続を ControlMaster で多重化するため、グループ追加は `make reprovision` 直後のセッションに反映されない（VM を再起動するまで permission denied になる）。
- `40-aws-vault.sh` — `~/.zprofile` のブロックは、マーカーの有無ではなく**中身を比較して差分があるときだけ** `sed` で消してから書き直す（`20-dev-env.sh` の `grep -qF` 方式だと、後から export を足したときに既存 VM へ伝播しない）。
- `50-starship.sh` — `40-aws-vault.sh` と同じ**中身の比較**方式。書き込み先は `~/.zshrc`（不変条件 #4 の例外）。ブロックは削除してから末尾に追記し直すので、`10-mise.sh` が書く mise ブロックより必ず後ろに来る（`mise activate` 後の PATH でないと `command -v starship` が通らない）。
- `60-sheldon.sh` — `50-starship.sh` と同じ**中身の比較**方式で `~/.zshrc` に書く（不変条件 #4 の例外）。番号が最後なのは、`sheldon source` が読み込む zsh-syntax-highlighting が upstream の要求で「最後に source される」必要があるため（`starship init zsh` が定義する ZLE ウィジェットより後でなければならない）。**この位置から動かさないこと。** プラグインの取得は `sheldon lock` を provision 時に走らせて済ませる（対話ログインまで持ち越すと、初回の `sheldon source` が clone の進捗を出して「`~/.zshrc` は何も出力しない」を破る）。`sheldon lock` は clone 済みのソースをスキップする（更新は `--update` のときだけ）ので、`mise install` と同じ理由でスタンプは置かない。

### 3. provision スクリプト内で `{{` を 2 個続けて書かない

`provision[].file` で読み込まれたスクリプトは Lima 側で Go テンプレートとして解析される。シェルのパターンマッチ等で `{{` がリテラルとして現れると `unterminated character constant` でテンプレート処理が失敗し、**警告だけ出してそのファイルの `{{.Param.*}}` 展開が無効のまま通過する**（`make validate` は OK と表示される）。`make validate` の警告行は見逃さないこと。

これは `mode: data` で配る設定ファイルにも同じく効く（`file:` 経由で読まれるものはすべて対象）。`sheldon.plugins.toml` に sheldon 慣用の `use = [...]`（中括弧 2 個で始まるテンプレート記法でプラグイン名を埋めるもの）を書かないのはこのため。既定の `use` パターンで解決できるプラグインだけを入れる。

### 4. env と PATH は `~/.zprofile` 側で通す

VM のログインシェルは zsh（`05-zsh.sh` が `chsh` する）。zsh は `~/.zshrc` を**対話シェルでしか読まない**ため、`limactl shell <name> -- zsh -lc <cmd>` のような実行では `.zshrc` に書いた `mise activate` が効かない。`10-mise.sh` は `~/.zprofile` に mise の shims ディレクトリを PATH 追加し、`.zshrc` 側は対話シェル用に `mise activate zsh` を置く、という二段構えになっている。片方だけ直すと非対話実行やプローブが壊れる。

**`~/.zshenv` には書かないこと。** zsh の読み込み順は

```
/etc/zshenv → ~/.zshenv → /etc/zprofile → ~/.zprofile → (対話のみ) /etc/zshrc → ~/.zshrc
```

で、Ubuntu の `zsh-common` が置く `/etc/zprofile` が `emulate sh -c 'source /etc/profile'` を実行し、`/etc/profile` が PATH を**無条件に上書きする**。`~/.zshenv` はそれより前に走るので、そこに書いた mise の shims は消える。`~/.zprofile` だけが安全な置き場所。

例外は**対話シェルにしか意味の無いもの**だけ。`50-starship.sh` のプロンプト設定は `~/.zshrc` にのみ書く（非対話実行に持ち込む必要が無く、持ち込むと出力を汚す）。逆に env や PATH を `.zshrc` 側だけに書かないこと。

`~/.zshrc` は Claude Code のシェルスナップショット経由で非対話でも source されうるので、**何も出力しない**こと（`50-starship.sh` の `command -v starship` ガードと同じ理由）。

Makefile がログインシェルを起動する箇所（`dev-env` / `reprovision`）は `zsh -lc` にしてある。例外は `00-system-packages.sh` と `05-zsh.sh` を叩く 2 行で、こちらは素の `bash` で実行する。zsh をまだ持たない VM に `zsh -lc` を使うとブートストラップで詰むため。

### 5. `limactl shell` は既定で `/bin/bash -l` を実行する

**`chsh` も `$SHELL` も見ない。** ログインシェルを zsh にしても、`limactl shell <name>` が起動するのは `/bin/bash -l` のまま（`ps -p $$ -o args=` で実測できる）。`make shell` が `--shell /usr/bin/zsh` を渡しているのはこのため。外すと、env と PATH を `~/.zprofile` に移してある関係で `aws-vault: command not found` のような形で壊れる。

**フラグは INSTANCE より前に置くこと。** `limactl shell [flags] INSTANCE [COMMAND...]` なので、`limactl shell <name> --shell ...` のように後ろに置くと COMMAND の一部として渡り、ゲスト側の bash が `--: invalid option` で落ちる。`--reconnect` も同じ。

`chsh` が無意味なわけではない。ssh を直接使う経路（VS Code Remote-SSH、`ssh lima-<name>`）は passwd を見るので zsh になり、VM 内の `$SHELL` も zsh になる（Claude Code のシェルスナップショットが見るのはこちら）。

`dev-env` / `reprovision` は `-- zsh -lc '...'` と明示的に zsh を起動しているので `--shell` は要らない。

### 6. provision スクリプトの shebang は `#!/bin/bash` のまま

zsh 化したのは VM の**ログインシェル**であって、provision スクリプト自身ではない。`shell-lint.sh` と `shellcheck.yml` が `bash -n` + `shellcheck` をかけており、shellcheck は zsh 方言をサポートせずエラーになるので、`#!/bin/zsh` にすると hook と CI が両方落ちる。スクリプト内で zsh の機能が要るときは `zsh -c '...'` で明示的に呼び出す。

## 編集時のガード (`.claude/hooks/`)

上の不変条件のうち機械判定できるものは、`.claude/settings.json` の hooks で編集時に検査している。**ガードを回避するのではなく、指摘された不変条件の側を直すこと。**

- `lima-guard.sh` (PostToolUse / `lima/**`) — `limactl validate` の **警告を失敗として扱う**。不変条件 #3 のとおり limactl は警告を出しても exit 0 なので、`make validate` だけでは検知できない。あわせて不変条件 #1（`mounts: []`、`loadDotSSHPubKeys`、`forwardAgent`、`_default/mounts`）も検査する。
- `shell-lint.sh` (PostToolUse / `*.sh`) — `bash -n` + `shellcheck`。既存の provision スクリプトは全数クリーンなので、指摘が出たら新しく入れた側が原因。
- `workflow-lint.sh` (PostToolUse / `.github/workflows/*.yml`) — `actionlint` + `zizmor --offline`。`--offline` なのは編集のたびにネットワークと GitHub トークンに依存させないため。オンライン監査（`known-vulnerable-actions` 等）と `pinact` は CI 側（`actions-lint.yml`）でしか回らない。
- `no-secrets.sh` (PreToolUse) — PAT / AWS パスフレーズの実値がホスト側のファイルに入るのを止める（不変条件 #1）。README や provision の `export GITHUB_TOKEN=github_pat_...` のような**例示は通す**ので、プレースホルダを実値らしい文字列に書き換えないこと。

VM 内で走る claude 側（`--dangerously-skip-permissions`）にはハーネスを持ち込まない。隔離はあくまで「ホストへの到達経路が無いこと」で担保する。

## CI (`.github/workflows/`)

hook と同じ検査を、PR でリポジトリ全体に対してもう一度回す。**検査の実体は hook 側に置き、CI はそれを呼ぶだけにしてある**（`lima-validate.yml` は偽の hook ペイロードを `lima-guard.sh` に流し込んで判定させる）。不変条件を足すときに直すのは hook だけでよい。

| ワークフロー | 何を見るか | `paths:` |
| --- | --- | --- |
| `lima-validate.yml` | `limactl validate` + `lima-guard.sh` | `lima/**`, `.claude/hooks/lima-guard.sh`, `mise.toml` |
| `shellcheck.yml` | `git ls-files '*.sh'` 全数に `bash -n` + `shellcheck` | `**.sh`, `mise.toml` |
| `actions-lint.yml` | `actionlint` + `zizmor`（トークン付きでオンライン監査も）+ `pinact run --check` | `.github/workflows/**`, `mise.toml` |
| `renovate.yml` | 依存更新。`schedule` / `workflow_dispatch` のみ | — |

`paths:` はワークフロー単位にしか書けないので、検査ごとにファイルを分けてある。全ワークフローが `paths:` に `mise.toml` を含むのは、ツールのピンがそこにあるため。**hook や検査を足したら、対応するワークフローの `paths:` も足すこと。**

`paths:` を絞りすぎないこと。`renovate.jsonc` の automerge は「Renovate の PR は必ず `.github/workflows/**` かルートの `mise.toml` を触るので、CI が最低 1 つは走る」という前提の上に成り立っている。この前提が崩れると、チェックゼロのまま自動マージされる PR が生まれる。

## GitHub Actions の `uses:` は SHA ピンを維持する

タグは動かせるので、`actions/checkout@v5` のような参照はサプライチェーン上の穴になる。`uses:` はすべて `owner/repo@<40桁SHA> # vX.Y.Z` の形にしてあり、zizmor の `unpinned-uses` と CI の `pinact run --check` が両方から見張っている。

**SHA を手で書かないこと。** 既存の `uses:` の更新は Renovate（後述）が自動で PR にする。新しく `uses:` を足したときだけ、ローカルで `GITHUB_TOKEN=$(gh auth token) pinact run` を流して解決させる（横のバージョンコメントもここで一緒に付く。手書きするとコメントと SHA がズレて `--check` が落ちる）。タグを書いて pinact に解決させる方式なので、`renovatebot/github-action` のようにメジャータグ（`@v46`）を持たないアクションは、フルタグ（`@v46.2.1`）で書いてから流すこと。

`actions/checkout` には `persist-credentials: false` を付ける（zizmor の `artipacked`）。このリポジトリの CI は push しないので、`.git/config` に認証情報を残す理由が無い。

## 依存の更新は Renovate に任せる

`.github/workflows/renovate.yml`（self-hosted、毎日 05:00 JST）＋ `renovate.jsonc`（設定本体）。GitHub App のトークンで動かしているのは、`GITHUB_TOKEN` で作った PR が `pull_request` トリガーのワークフローを起動できず、CI green を前提にした automerge が成立しないため。App の secret（`RENOVATE_APP_ID` / `RENOVATE_APP_PRIVATE_KEY`）はリポジトリの Actions secrets にあり、ホスト側のファイルには置かない。

`renovate.jsonc` で明示的に落としている `lima/provision/mise.vm.toml` のルールを消さないこと。Renovate の mise manager の既定パターン `**/{,.}mise{,.*}.toml` はこのファイル名にも一致するため、ルールを外すと VM 内のツール（`python` のピン等）に黙って PR が飛ぶようになる。

`config:best-practices` の `helpers:pinGitHubActionDigests` が書く形は pinact の期待する形と同じなので、Renovate の PR でも `pinact run --check` は通る。設定を変えたら `npx --yes --package renovate -- renovate-config-validator --strict --no-global renovate.jsonc` で検証する（CI では回していない）。

## ツールの追加

mise の設定ファイルが 2 つある。**どちらに足すのかを取り違えないこと。**

| ファイル | 何が入るか | 反映方法 | Renovate |
| --- | --- | --- | --- |
| `lima/provision/mise.vm.toml` | **VM 内**のランタイム・CLI | `make reprovision` | 対象外（`renovate.jsonc` で無効化） |
| `mise.toml`（リポジトリルート） | **ホスト側**でこのリポジトリを開発するためのツール（`limactl` / `shellcheck` / `jq` / `actionlint` / `zizmor` / `pinact`） | `mise install` | 対象 |

VM 側は使い捨て前提なので `latest` 中心、ホスト側は再現性を優先してバージョンをピン留めする、という使い分けにしている。ホスト側の `lima` を下げると既存インスタンス（`~/.lima/<name>`）が壊れうるので、上げる方向にだけ動かすこと。

VM 側のランタイムや CLI は原則すべて mise 管理下に置く。apt は mise で入らない土台（コンパイラ、共有ライブラリ等）だけに留める。追加前に `mise registry | grep <name>` で登録名を確認すること（`limactl` ではなく `lima` のように、コマンド名と登録名がずれることがある）。

`lima/provision/mise.vm.toml` を `mise.toml` に戻さないこと。その名前だと `lima/provision/` を cwd にしたときに mise がホスト側の設定として読んでしまい、VM 用のツール定義がホストに漏れる。

zsh のプラグインは mise ではなく **sheldon** の担当で、定義は `lima/provision/sheldon.plugins.toml`（VM の `~/.config/sheldon/plugins.toml` に `mode: data` で配る）。mise 側に入るのは sheldon 本体だけ。ファイル名に `.vm` を挟んでいないのは、sheldon が mise と違って cwd の上位探索をせず、ホスト側に漏れる経路が無いため。プラグインを足すときは不変条件 #3 の中括弧制限に注意する。

docker（`docker.io` / `docker-buildx` / `docker-compose-v2`）はデーモン + systemd 管理で mise に載らないため、`00-system-packages.sh` の `PACKAGES` に置いている例外。`zsh` も mise registry に登録が無いので同じく apt 側の例外（配線と `chsh` は `05-zsh.sh`）。同種の例外を足すときも、パッケージ追加は `PACKAGES` に入れる（sha256 スタンプが自動で再実行を引く）だけにして、サービス設定やシェル配線は別スクリプトに切り出す。

`lima/claude-sandbox.yaml` の readiness probe は、mise shims の `node` と `claude`（最大 900 秒待つ）、および `docker info` の疎通（180 秒）を待ち受ける。`mise.vm.toml` からこれらを外したり docker をやめたりすると、`make up` はタイムアウトまで待ってから失敗する。ツールを**減らす**ときは probe も合わせて直すこと。

## aws-vault のバックエンドを secret-service にしない

「Ubuntu のキーチェーンに入れる」構成は**技術的には動く**（実測で確認済み: `dbus-user-session` 導入済みでユーザーセッションバスがあり、`loginctl` の `Linger=yes` なので一度アンロックすれば VM の電源が落ちるまで有効）。それでも採らないのは、gnome-keyring の apt 追加・デーモン常駐・ブートごとのアンロックヘルパ・既定コレクションの手当て（aws-vault 既定の `awsvault` コレクションは、存在しないと作成に GUI プロンプタが要るため headless では作れず、`login` に相乗りさせる必要がある）と、この VM に見合わない構成の複雑さを持ち込むため。

「aws-vault が使えない」を secret-service や gnome-keyring の導入で解決しないこと。file バックエンドのまま原因を潰す。
