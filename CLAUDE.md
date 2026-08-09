# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

macOS 上に Lima で Claude Code 実行用の隔離 VM を立てるための設定リポジトリ。アプリケーションコードは無く、成果物は Lima テンプレート・シェルスクリプト・Makefile のみ。ユーザー向けの説明は `README.md` にある。

## コマンド

```sh
make validate       # Lima テンプレートの検証。YAML やスクリプトを触ったら必ず最初に通す
make up             # 作成 (初回のみ) + 起動 + プロビジョニング
make claude         # up してから VM 内の ~/workspace で claude を起動する (この VM の主目的)
make reprovision    # lima/provision/ の変更だけを再適用する
make recreate       # 破棄して作り直す
make status         # 状態確認
```

テストフレームワークは無い。検証は実際に VM を起動して確かめる。

## 変更を反映する経路が 2 つある

これを取り違えると「直したのに反映されない」で時間を溶かす。

- **`lima/provision/` を変えた** → `make reprovision`。スクリプトを VM に転送して直接実行するので数十秒で終わる。
- **`lima/claude-code.yaml` を変えた** → `make recreate`。Lima は作成時にテンプレートの内容（provision スクリプトの中身を含む）をインスタンス側 `~/.lima/<name>/lima.yaml` にコピーするため、既存インスタンスに `make up` してもリポジトリ側の yaml 変更は読まれない。

`make reprovision` は yaml の `mode: data` に相当する処理（`mise.vm.toml` → `~/.config/mise/config.toml` の配置）も自前で再現している。yaml 側の provision エントリを増減させたら、Makefile の `reprovision` ターゲットも合わせて更新すること。

`20-dev-env.sh` だけは `dev-env` ターゲットに切り出してあり、`up` と `reprovision` の両方がこれを呼ぶ。ホストの git identity を env で流し込む唯一の経路なので、片方から外さないこと。

### `param:` は使わない

Lima の `param` はインスタンス**作成時**にしか渡せず、既存 VM への `make up`（`limactl start <name>` 経路）では変更できない。さらに `make reprovision` はスクリプトを生のまま実行するので `{{.Param.*}}` が展開されない。ホストから VM に値を渡したいときは、`dev-env` のように `limactl shell -- env KEY=... bash -lc ...` を使う。

## 不変条件

### 1. 隔離モデルを単独で壊さない

`lima/claude-code.yaml` の `mounts: []`、`ssh.loadDotSSHPubKeys: false`、`ssh.forwardAgent: false` は、`make claude` が `--dangerously-skip-permissions` を渡している前提そのもの。マウントや agent forwarding を足すと、VM 内のエージェントがホストの認証情報やソースに到達できるようになる。

`base:` に `template:_default/mounts` を追加してはいけない（ホームが読み取り専用でマウントされる）。他の Lima テンプレートをコピーしてくるときに紛れ込みやすい。

隔離を緩める必要が出たら、`make claude` から `--dangerously-skip-permissions` を外すこととセットで検討する。

GitHub への認証は **HTTPS + 環境変数の fine-grained PAT** だけを経路にする。「push できない」を ssh 鍵の配置や `forwardAgent: true` で解決しないこと。トークンはユーザーが VM 内で `export` するものであり、ホスト側（Makefile・yaml・`~/.lima/<name>/`）には一切書かない。

AWS のクレデンシャルは **aws-vault の file バックエンド**だけを経路にする。平文の `~/.aws/credentials` を置かない。パスフレーズ（`AWS_VAULT_FILE_PASSPHRASE`）も PAT と同じ扱いで、ホスト側（Makefile・yaml・`~/.lima/<name>/`）にも provision にも書かない。パスフレーズを `export` した状態ではエージェントも `aws-vault exec` できてしまうので、README には「投入するのは最小権限ロール / 短命クレデンシャルに限る」と明記してある。この非対称性（PAT・AWS だけ穴を開けている）を README の「隔離の境界線」と食い違わせないこと。

### 2. provision スクリプトは毎ブート実行される

Lima の provision は cloud-init の `scripts_per_boot` として登録されるため、VM を再起動するたびに全スクリプトが走る。処理を追加するときは必ずガードを付ける:

- `00-system-packages.sh` — パッケージリストの sha256 をスタンプファイル名に埋め込み、`/var/lib/sandbox-vm/apt.<hash>` があれば `apt-get update` ごとスキップする。リストを変えるとハッシュが変わって自動的に再実行される。
- `10-mise.sh` — mise 本体は `-x` チェック、シェル統合は `# >>> sandbox-vm mise >>>` マーカーの `grep -qF` で判定。`mise install` は既存バージョンをスキップするので**あえてスタンプを置かない**（置くと `latest` 指定の `claude` が上流更新に追随できなくなる）。
- `20-dev-env.sh` — 書き込みの種類ごとに冪等性の担保が違う。`user.name` / `user.email` は `GIT_USER_NAME` / `GIT_USER_EMAIL` が**非空のときだけ**上書きする（ホスト側を単一の真実にするため。ブート経路では env が空なので VM 内の設定が残る）。`init.defaultBranch` は未設定のときだけ書く。`ghq.root` と credential helper 関連は単一値なので `git config --global` で上書きし続けてよい。`url.insteadOf` は多値キーなので `--replace-all` → `--add` の順で書く（`--add` だけだとブートごとに増殖する）。`~/.profile` への `GIT_TERMINAL_PROMPT=0` は `# >>> sandbox-vm git >>>` マーカーの `grep -qF` で判定する。`~/.claude` には触れない（対話ログインの成果物が消えるため）。
- `30-docker.sh` — `docker.socket` の drop-in は**内容を比較して差分があるときだけ**書き、書き換えたときだけ `daemon-reload` とサービス再起動を行う（毎ブート restart するとブートが遅くなる）。ソケットの権限は `usermod -aG docker` ではなく `SocketUser` で与える。補助グループは SSH 認証時に確定し、Lima は SSH 接続を ControlMaster で多重化するため、グループ追加は `make reprovision` 直後のセッションに反映されない（VM を再起動するまで permission denied になる）。
- `40-aws-vault.sh` — `~/.profile` のブロックは、マーカーの有無ではなく**中身を比較して差分があるときだけ** `sed` で消してから書き直す（`20-dev-env.sh` の `grep -qF` 方式だと、後から export を足したときに既存 VM へ伝播しない）。
- `50-starship.sh` — `40-aws-vault.sh` と同じ**中身の比較**方式。書き込み先は `~/.bashrc`（不変条件 #4 の例外）。ブロックは削除してから末尾に追記し直すので、`10-mise.sh` が書く mise ブロックより必ず後ろに来る（`mise activate` 後の PATH でないと `command -v starship` が通らない）。

### 3. provision スクリプト内で `{{` を 2 個続けて書かない

`provision[].file` で読み込まれたスクリプトは Lima 側で Go テンプレートとして解析される。シェルのパターンマッチ等で `{{` がリテラルとして現れると `unterminated character constant` でテンプレート処理が失敗し、**警告だけ出してそのファイルの `{{.Param.*}}` 展開が無効のまま通過する**（`make validate` は OK と表示される）。`make validate` の警告行は見逃さないこと。

### 4. PATH は `~/.profile` 側で通す

Ubuntu の `~/.bashrc` は非対話シェルで冒頭 return するため、`limactl shell <name> -- <cmd>` のような実行では `.bashrc` に書いた `mise activate` が効かない。`10-mise.sh` は `~/.profile` に mise の shims ディレクトリを PATH 追加し、`.bashrc` 側は対話シェル用に `mise activate bash` を置く、という二段構えになっている。片方だけ直すと非対話実行やプローブが壊れる。

例外は**対話シェルにしか意味の無いもの**だけ。`50-starship.sh` のプロンプト設定は `~/.bashrc` にのみ書く（非対話実行に持ち込む必要が無く、持ち込むと出力を汚す）。逆に env や PATH を `.bashrc` 側だけに書かないこと。

## 編集時のガード (`.claude/hooks/`)

上の不変条件のうち機械判定できるものは、`.claude/settings.json` の hooks で編集時に検査している。**ガードを回避するのではなく、指摘された不変条件の側を直すこと。**

- `lima-guard.sh` (PostToolUse / `lima/**`) — `limactl validate` の **警告を失敗として扱う**。不変条件 #3 のとおり limactl は警告を出しても exit 0 なので、`make validate` だけでは検知できない。あわせて不変条件 #1（`mounts: []`、`loadDotSSHPubKeys`、`forwardAgent`、`_default/mounts`）も検査する。
- `shell-lint.sh` (PostToolUse / `*.sh`) — `bash -n` + `shellcheck`。既存の provision スクリプトは全数クリーンなので、指摘が出たら新しく入れた側が原因。
- `no-secrets.sh` (PreToolUse) — PAT / AWS パスフレーズの実値がホスト側のファイルに入るのを止める（不変条件 #1）。README や provision の `export GITHUB_TOKEN=github_pat_...` のような**例示は通す**ので、プレースホルダを実値らしい文字列に書き換えないこと。

VM 内で走る claude 側（`--dangerously-skip-permissions`）にはハーネスを持ち込まない。隔離はあくまで「ホストへの到達経路が無いこと」で担保する。

## ツールの追加

mise の設定ファイルが 2 つある。**どちらに足すのかを取り違えないこと。**

| ファイル | 何が入るか | 反映方法 |
| --- | --- | --- |
| `lima/provision/mise.vm.toml` | **VM 内**のランタイム・CLI | `make reprovision` |
| `mise.toml`（リポジトリルート） | **ホスト側**でこのリポジトリを開発するためのツール（`limactl` / `shellcheck` / `jq`） | `mise install` |

VM 側は使い捨て前提なので `latest` 中心、ホスト側は再現性を優先してバージョンをピン留めする、という使い分けにしている。ホスト側の `lima` を下げると既存インスタンス（`~/.lima/<name>`）が壊れうるので、上げる方向にだけ動かすこと。

VM 側のランタイムや CLI は原則すべて mise 管理下に置く。apt は mise で入らない土台（コンパイラ、共有ライブラリ等）だけに留める。追加前に `mise registry | grep <name>` で登録名を確認すること（`limactl` ではなく `lima` のように、コマンド名と登録名がずれることがある）。

`lima/provision/mise.vm.toml` を `mise.toml` に戻さないこと。その名前だと `lima/provision/` を cwd にしたときに mise がホスト側の設定として読んでしまい、VM 用のツール定義がホストに漏れる。

docker（`docker.io` / `docker-buildx` / `docker-compose-v2`）はデーモン + systemd 管理で mise に載らないため、`00-system-packages.sh` の `PACKAGES` に置いている例外。同種の例外を足すときも、パッケージ追加は `PACKAGES` に入れる（sha256 スタンプが自動で再実行を引く）だけにして、サービス設定は別スクリプトに切り出す。

## aws-vault のバックエンドを secret-service にしない

「Ubuntu のキーチェーンに入れる」構成は**技術的には動く**（実測で確認済み: `dbus-user-session` 導入済みでユーザーセッションバスがあり、`loginctl` の `Linger=yes` なので一度アンロックすれば VM の電源が落ちるまで有効）。それでも採らないのは、gnome-keyring の apt 追加・デーモン常駐・ブートごとのアンロックヘルパ・既定コレクションの手当て（aws-vault 既定の `awsvault` コレクションは、存在しないと作成に GUI プロンプタが要るため headless では作れず、`login` に相乗りさせる必要がある）と、この VM に見合わない構成の複雑さを持ち込むため。

「aws-vault が使えない」を secret-service や gnome-keyring の導入で解決しないこと。file バックエンドのまま原因を潰す。
