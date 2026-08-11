# CONTRIBUTING

このリポジトリ自体（Lima テンプレート・provision スクリプト・CI）を編集する人向けの手引き。VM を立てて使うだけなら [README.md](README.md) で足りる。以下のツールはどれも VM の利用には不要で、リポジトリを触るときだけ要る。

## 開発環境のセットアップ

ホスト側のツールは [mise](https://mise.jdx.dev/)（`brew install mise`）で管理している。

**Homebrew などで mise を入れただけではシェルで有効にならない**。`brew install mise` が置くのは `mise` コマンド本体だけで、管理下のツール（`limactl` など）を PATH に載せるのはシェル側の有効化処理。これを飛ばすと `mise install` は成功するのに `limactl: command not found` になる。使っているシェルの rc ファイルに一度だけ書く:

```sh
# zsh (macOS の既定)
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc

# bash
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
```

書いたらシェルを開き直す（`exec $SHELL -l`）。設定を汚したくない場合は、有効化せずに `mise exec -- limactl ...` や `mise x -- make validate` の形で都度呼んでもよい。

有効化できたら、クローン後に一度だけ:

```sh
mise trust && mise install
```

これで `limactl` に加えて、`.claude/hooks/` と CI が使う `shellcheck` / `jq` / `actionlint` / `zizmor` / `pinact` が揃う。`which limactl` が `~/.local/share/mise/` 配下を指していれば通っている。

mise の設定ファイルは 2 つあり、**どちらに足すのかを取り違えないこと**:

| ファイル | 何が入るか | 反映方法 |
| --- | --- | --- |
| `mise.toml`（ルート） | ホスト側の開発ツール。CI の再現性と既存 VM との対応のためバージョンをピン留めする | `mise install` |
| `lima/provision/mise.vm.toml` | VM 内のランタイム・CLI。使い捨て前提なので `latest` 中心 | `make reprovision` |

ホスト側の `lima` を下げると既存インスタンス（`~/.lima/<name>`）が壊れうるので、上げる方向にだけ動かすこと。

## 変更を反映する経路が 2 つある

取り違えると「直したのに反映されない」で時間を溶かす。

- **`lima/provision/` を変えた** → `make reprovision`（VM は作り直さない）
- **`lima/claude-sandbox.yaml` を変えた** → `make recreate`

Lima は作成時にテンプレートの内容を `~/.lima/<name>/lima.yaml` にコピーするため、既存インスタンスに `make up` してもリポジトリ側の yaml 変更は読まれない。理由と例外は `CLAUDE.md` に詳しく書いてある。

provision スクリプトを 1 本足すときに触るのは yaml だけでよい。Makefile の `LOGIN_SCRIPTS` が `lima/provision/*.sh` を番号順に glob している。特別扱い（root で叩く / env を渡す）が要るときだけ `BOOTSTRAP_SCRIPTS` と `SKIP_SCRIPTS` を直す。`mode: data` の配布ファイルを足したときは `DATA_FILES` も直すこと。

VM のシェル設定は `~/.zprofile` / `~/.zshrc` に直接書かず、`~/.config/claude-sandbox/{zprofile,zshrc}.d/` に自分の番号を冠した断片を置く（`05-zsh.sh` が書くローダが番号順に source する）。詳細は `CLAUDE.md` 不変条件 #4。

## 編集時のガード（`.claude/hooks/`）

Claude Code で編集すると、`.claude/settings.json` の hooks が該当ファイルに対して検査を走らせる。**ガードを回避するのではなく、指摘された側を直すこと。**

- `lima-guard.sh`（`lima/**`）— `limactl validate` の警告を失敗として扱い、隔離設定（`mounts: []` / `loadDotSSHPubKeys` / `forwardAgent`）も検査する
- `shell-lint.sh`（`*.sh`）— `bash -n` + `shellcheck`
- `workflow-lint.sh`（`.github/workflows/*.yml`）— `actionlint` + `zizmor --offline`
- `no-secrets.sh`（全書き込み）— PAT や AWS パスフレーズの実値がホスト側のファイルに入るのを止める

ペイロードの読み取りと報告は `_common.sh`（source 専用、実行ビット無し）に括り出してある。hook を足すときの注意点は `CLAUDE.md` に書いてある（`# shellcheck source=/dev/null` を忘れると hook が自分自身を落とす）。

`make validate` は `limactl validate` を素で叩くだけで、**警告が出ても成功する**。合否は hook と CI が判定する。

hook は「今編集したファイル」にしか走らないので、まとめて直したあとは CI と同じ全数検査をローカルで回す:

```sh
git ls-files -z '*.sh' | xargs -0 -n1 bash -n && git ls-files -z '*.sh' | xargs -0 shellcheck
actionlint -color && GH_TOKEN=$(gh auth token) zizmor .github/workflows && pinact run --check
printf '{"tool_input":{"file_path":"%s"}}' "$PWD/lima/claude-sandbox.yaml" | .claude/hooks/lima-guard.sh
```

最後の 1 行は `lima-validate.yml` がやっていることと同じ（偽の hook ペイロードを流し込む）。hook はパスからリポジトリルートを求めるので、`file_path` は**絶対パス**で渡すこと。

テストフレームワークは無い。最終的な検証は実際に VM を起動して確かめる。

## CI（`.github/workflows/`）

hook と同じ検査を、PR でリポジトリ全体に対してもう一度回す。**検査の実体は hook 側に置き、CI はそれを呼ぶだけにしてある**ので、不変条件を足すときに直すのは hook だけでよい。

| ワークフロー | 何を見るか |
| --- | --- |
| `lima-validate.yml` | `limactl validate` + `lima-guard.sh` |
| `shellcheck.yml` | `git ls-files '*.sh'` 全数に `bash -n` + `shellcheck` |
| `actions-lint.yml` | `actionlint` + `zizmor`（トークン付きでオンライン監査も）+ `pinact run --check` |
| `renovate.yml` | 依存更新（`schedule` / `workflow_dispatch` のみ） |

`paths:` はワークフロー単位にしか書けないので、検査ごとにファイルを分けてある。**hook や検査を足したら、対応するワークフローの `paths:` も足すこと。**

## 依存の更新は Renovate に任せる

依存（`mise.toml` のツールと GitHub Actions の `uses:`）の更新は Renovate が毎日 05:00 JST に見て PR にする。設定は `renovate.jsonc`、実行は `.github/workflows/renovate.yml`。digest / pin / patch の更新は CI が green なら自動でマージされ、それ以外は Dependency Dashboard の issue から操作できる。VM 内のツール（`lima/provision/mise.vm.toml`）は使い捨て前提なので対象外。

`renovate.jsonc` を変えたら、CI では回していないのでローカルで検証する:

```sh
npx --yes --package renovate -- renovate-config-validator --strict --no-global renovate.jsonc
```

## `uses:` の SHA ピン

タグは動かせるので、`uses:` はすべて `owner/repo@<40桁SHA> # vX.Y.Z` の形にしてある（zizmor の `unpinned-uses` と `pinact run --check` が見張っている）。

**SHA を手で書かないこと。** 既存分の更新は Renovate がやる。新しく `uses:` を足したときだけ、タグを書いた状態でローカルから流して解決させる:

```sh
GITHUB_TOKEN=$(gh auth token) pinact run
```

横のバージョンコメントもここで一緒に付く（手書きするとコメントと SHA がズレて `--check` が落ちる）。メジャータグを持たないアクションはフルタグ（`@v46.2.1`）で書いてから流すこと。

## リポジトリ運用のファイル

VM 側の構成は README の「構成」にある。それ以外:

```
mise.toml                       ホスト側の開発ツール (ピン留め)
renovate.jsonc                  Renovate の設定本体
.claude/hooks/                  編集時のガード (CI から呼ばれる実体でもある)
.github/workflows/              CI
CLAUDE.md                       不変条件と設計の背景 (エージェント向け、人間が読んでもよい)
```

隔離モデルや provision の冪等性など、壊してはいけない不変条件の全文は `CLAUDE.md` にある。`lima/` や `lima/provision/` を触る前に一読すること。
