INSTANCE ?= claude-sandbox
TEMPLATE  := lima/claude-sandbox.yaml
PROVISION := lima/provision

# VM 内に設定する git identity。既定値はホストの git config から拾う。
#   make up GIT_USER_EMAIL=work@example.com   のように上書きできる。
# Lima の param は作成時にしか渡せないので、env として毎回流し込む方式にしている。
GIT_USER_NAME  ?= $(shell git config --get user.name)
GIT_USER_EMAIL ?= $(shell git config --get user.email)

# reprovision で流す provision スクリプト。実行順は $(TEMPLATE) と同じファイル名の番号順。
#   BOOTSTRAP_SCRIPTS ... 素の bash で叩くもの (下の reprovision に直書き)
#   SKIP_SCRIPTS      ... ここでは走らせないもの (dev-env が env 付きで叩く)
#   LOGIN_SCRIPTS     ... 残り全部。スクリプトを足しても Makefile は触らなくてよい
BOOTSTRAP_SCRIPTS := 00-system-packages.sh 05-zsh.sh
SKIP_SCRIPTS      := 20-dev-env.sh
LOGIN_SCRIPTS     := $(filter-out $(BOOTSTRAP_SCRIPTS) $(SKIP_SCRIPTS),$(notdir $(sort $(wildcard $(PROVISION)/*.sh))))

# $(TEMPLATE) の provision mode: data を reprovision 経路で再現するためのリスト。
# 形式は <リポジトリ内のファイル名>:<VM の HOME からの相対パス>。yaml 側と対応させること。
DATA_FILES := mise.vm.toml:.config/mise/config.toml \
              sheldon.plugins.toml:.config/sheldon/plugins.toml

.DEFAULT_GOAL := up
.PHONY: up shell dev-env reprovision recreate stop destroy status validate ssh-config help

## up: VM を作成 (初回のみ) して起動し、プロビジョニングを流す
up:
	@if limactl list -q 2>/dev/null | grep -qx '$(INSTANCE)'; then \
		echo '==> starting existing instance: $(INSTANCE)'; \
		limactl start '$(INSTANCE)'; \
	else \
		echo '==> creating instance from $(TEMPLATE) (初回は 10 分程度かかります)'; \
		limactl start --name='$(INSTANCE)' '$(TEMPLATE)' --progress --timeout=20m -y; \
	fi
	@$(MAKE) --no-print-directory dev-env

## shell: VM にログインする
#
# --shell が要る。limactl shell は既定で /bin/bash -l を実行し、chsh も $SHELL も見ない
# (ssh 経由の VS Code Remote-SSH は passwd を見るので、そちらは chsh だけで zsh になる)。
# フラグは INSTANCE より前に置くこと。後ろに置くと COMMAND 扱いされて壊れる。
shell: up
	limactl shell --shell /usr/bin/zsh '$(INSTANCE)'

## dev-env: git identity など VM 内の開発環境設定を (再) 適用する
#
# ホストの git identity を VM に反映する唯一の経路。up と reprovision の両方から呼ばれる。
# PAT はここを通さない (ユーザーが VM 内で環境変数にセットする)。
#
# up からも単独で呼ばれるので、reprovision の copy -r とは別に自分でコピーする。
# reprovision 経由だと /tmp/provision/20-dev-env.sh にも同じものが置かれるが、走るのはこちら。
dev-env:
	@limactl copy '$(PROVISION)/20-dev-env.sh' '$(INSTANCE):/tmp/20-dev-env.sh'
	limactl shell '$(INSTANCE)' -- env \
		GIT_USER_NAME='$(GIT_USER_NAME)' \
		GIT_USER_EMAIL='$(GIT_USER_EMAIL)' \
		zsh -lc 'bash /tmp/20-dev-env.sh'

## reprovision: provision/ 配下のスクリプトだけを再適用する (VM は作り直さない)
#
# ログインシェル経由 (zsh -lc) にしているのは ~/.zprofile の PATH を効かせるため。
# 00 と 05 だけは素の bash で叩く。zsh をまだ持たない VM に対して zsh -lc を使うと
# ブートストラップで詰むうえ、この 2 つは mise の PATH を必要としない。
#
# ループの中で || exit 1 しているのは、make がレシピ 1 行を 1 つの sh -c で走らせる
# (= set -e が効かない) ため。これが無いと途中のスクリプトが失敗しても最後まで進む。
reprovision:
	limactl copy -r '$(PROVISION)' '$(INSTANCE):/tmp/'
	limactl shell '$(INSTANCE)' -- sudo bash /tmp/provision/00-system-packages.sh
	limactl shell '$(INSTANCE)' -- bash /tmp/provision/05-zsh.sh
	@for pair in $(DATA_FILES); do \
		src=$${pair%%:*}; dst=$${pair#*:}; \
		echo "==> $$dst"; \
		limactl shell '$(INSTANCE)' -- zsh -lc "install -D -m 0644 /tmp/provision/$$src \$$HOME/$$dst" || exit 1; \
	done
	@for script in $(LOGIN_SCRIPTS); do \
		echo "==> $$script"; \
		limactl shell '$(INSTANCE)' -- zsh -lc "bash /tmp/provision/$$script" || exit 1; \
	done
	@$(MAKE) --no-print-directory dev-env

## recreate: VM を破棄して作り直す ($(TEMPLATE) 自体の変更を反映するときに使う)
recreate: destroy up

## stop: VM を停止する (ディスクは残る)
stop:
	limactl stop '$(INSTANCE)'

## destroy: VM を削除する (VM 内のデータと claude の認証情報も消える)
destroy:
	-limactl delete -f '$(INSTANCE)'

## status: VM の状態を表示する
status:
	limactl list '$(INSTANCE)'

## validate: Lima テンプレートを検証する
validate:
	limactl validate '$(TEMPLATE)'

## ssh-config: VS Code Remote-SSH 等から繋ぐための設定を表示する
ssh-config:
	@echo '~/.ssh/config に以下を追記すると `ssh lima-$(INSTANCE)` で繋がります:'
	@echo
	@echo "  Include $$(limactl list '$(INSTANCE)' --format '{{.Dir}}')/ssh.config"

## help: このヘルプを表示する
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/^## /  make /'
