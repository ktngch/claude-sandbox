# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

macOS 上に Lima で Claude Code 実行用の隔離 VM を立てるための設定リポジトリ。アプリケーションコードは無く、成果物は Lima テンプレート・シェルスクリプト・Makefile のみ。ユーザー向けの説明は `README.md` にある。

## コマンド

```sh
make validate       # Lima テンプレートの検証。YAML やスクリプトを触ったら必ず最初に通す
make up             # 作成 (初回のみ) + 起動 + プロビジョニング
make reprovision    # lima/provision/ の変更だけを再適用する
make recreate       # 破棄して作り直す
make status         # 状態確認
```

テストフレームワークは無い。検証は実際に VM を起動して確かめる。

## 変更を反映する経路が 2 つある

これを取り違えると「直したのに反映されない」で時間を溶かす。

- **`lima/provision/` を変えた** → `make reprovision`。スクリプトを VM に転送して直接実行するので数十秒で終わる。
- **`lima/claude-code.yaml` を変えた** → `make recreate`。Lima は作成時にテンプレートの内容（provision スクリプトの中身を含む）をインスタンス側 `~/.lima/<name>/lima.yaml` にコピーするため、既存インスタンスに `make up` してもリポジトリ側の yaml 変更は読まれない。

`make reprovision` は yaml の `mode: data` に相当する処理（`mise.toml` → `~/.config/mise/config.toml` の配置）も自前で再現している。yaml 側の provision エントリを増減させたら、Makefile の `reprovision` ターゲットも合わせて更新すること。

`20-dev-env.sh` だけは `dev-env` ターゲットに切り出してあり、`up` と `reprovision` の両方がこれを呼ぶ。ホストの git identity を env で流し込む唯一の経路なので、片方から外さないこと。

### `param:` は使わない

Lima の `param` はインスタンス**作成時**にしか渡せず、既存 VM への `make up`（`limactl start <name>` 経路）では変更できない。さらに `make reprovision` はスクリプトを生のまま実行するので `{{.Param.*}}` が展開されない。ホストから VM に値を渡したいときは、`dev-env` のように `limactl shell -- env KEY=... bash -lc ...` を使う。

## 不変条件

### 1. 隔離モデルを単独で壊さない

`lima/claude-code.yaml` の `mounts: []`、`ssh.loadDotSSHPubKeys: false`、`ssh.forwardAgent: false` は、`make claude` が `--dangerously-skip-permissions` を渡している前提そのもの。マウントや agent forwarding を足すと、VM 内のエージェントがホストの認証情報やソースに到達できるようになる。

`base:` に `template:_default/mounts` を追加してはいけない（ホームが読み取り専用でマウントされる）。他の Lima テンプレートをコピーしてくるときに紛れ込みやすい。

隔離を緩める必要が出たら、`make claude` から `--dangerously-skip-permissions` を外すこととセットで検討する。

GitHub への認証は **HTTPS + 環境変数の fine-grained PAT** だけを経路にする。「push できない」を ssh 鍵の配置や `forwardAgent: true` で解決しないこと。トークンはユーザーが VM 内で `export` するものであり、ホスト側（Makefile・yaml・`~/.lima/<name>/`）には一切書かない。

### 2. provision スクリプトは毎ブート実行される

Lima の provision は cloud-init の `scripts_per_boot` として登録されるため、VM を再起動するたびに全スクリプトが走る。処理を追加するときは必ずガードを付ける:

- `00-system-packages.sh` — パッケージリストの sha256 をスタンプファイル名に埋め込み、`/var/lib/sandbox-vm/apt.<hash>` があれば `apt-get update` ごとスキップする。リストを変えるとハッシュが変わって自動的に再実行される。
- `10-mise.sh` — mise 本体は `-x` チェック、シェル統合は `# >>> sandbox-vm mise >>>` マーカーの `grep -qF` で判定。`mise install` は既存バージョンをスキップするので**あえてスタンプを置かない**（置くと `latest` 指定の `claude` が上流更新に追随できなくなる）。
- `20-dev-env.sh` — 書き込みの種類ごとに冪等性の担保が違う。`user.name` / `user.email` は `GIT_USER_NAME` / `GIT_USER_EMAIL` が**非空のときだけ**上書きする（ホスト側を単一の真実にするため。ブート経路では env が空なので VM 内の設定が残る）。`init.defaultBranch` は未設定のときだけ書く。`ghq.root` と credential helper 関連は単一値なので `git config --global` で上書きし続けてよい。`url.insteadOf` は多値キーなので `--replace-all` → `--add` の順で書く（`--add` だけだとブートごとに増殖する）。`~/.profile` への `GIT_TERMINAL_PROMPT=0` は `# >>> sandbox-vm git >>>` マーカーの `grep -qF` で判定する。`~/.claude` には触れない（対話ログインの成果物が消えるため）。

### 3. provision スクリプト内で `{{` を 2 個続けて書かない

`provision[].file` で読み込まれたスクリプトは Lima 側で Go テンプレートとして解析される。シェルのパターンマッチ等で `{{` がリテラルとして現れると `unterminated character constant` でテンプレート処理が失敗し、**警告だけ出してそのファイルの `{{.Param.*}}` 展開が無効のまま通過する**（`make validate` は OK と表示される）。`make validate` の警告行は見逃さないこと。

### 4. PATH は `~/.profile` 側で通す

Ubuntu の `~/.bashrc` は非対話シェルで冒頭 return するため、`limactl shell <name> -- <cmd>` のような実行では `.bashrc` に書いた `mise activate` が効かない。`10-mise.sh` は `~/.profile` に mise の shims ディレクトリを PATH 追加し、`.bashrc` 側は対話シェル用に `mise activate bash` を置く、という二段構えになっている。片方だけ直すと非対話実行やプローブが壊れる。

## ツールの追加

ランタイムや CLI は原則すべて mise 管理下に置く（`lima/provision/mise.toml`）。apt は mise で入らない土台（コンパイラ、共有ライブラリ等）だけに留める。追加前に `mise registry | grep <name>` で登録名を確認すること。
