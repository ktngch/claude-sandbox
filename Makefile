INSTANCE ?= claude-sandbox
TEMPLATE  := lima/claude-sandbox.yaml
PROVISION := lima/provision

# VM 内に設定する git identity。既定値はホストの git config から拾う。
#   make up GIT_USER_EMAIL=work@example.com   のように上書きできる。
# Lima の param は作成時にしか渡せないので、env として毎回流し込む方式にしている。
GIT_USER_NAME  ?= $(shell git config --get user.name)
GIT_USER_EMAIL ?= $(shell git config --get user.email)

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
reprovision:
	limactl copy -r '$(PROVISION)' '$(INSTANCE):/tmp/'
	limactl shell '$(INSTANCE)' -- sudo bash /tmp/provision/00-system-packages.sh
	limactl shell '$(INSTANCE)' -- bash /tmp/provision/05-zsh.sh
	limactl shell '$(INSTANCE)' -- zsh -lc 'install -D -m 0644 /tmp/provision/mise.vm.toml ~/.config/mise/config.toml'
	limactl shell '$(INSTANCE)' -- zsh -lc 'install -D -m 0644 /tmp/provision/sheldon.plugins.toml ~/.config/sheldon/plugins.toml'
	limactl shell '$(INSTANCE)' -- zsh -lc 'bash /tmp/provision/10-mise.sh'
	limactl shell '$(INSTANCE)' -- zsh -lc 'bash /tmp/provision/30-docker.sh'
	limactl shell '$(INSTANCE)' -- zsh -lc 'bash /tmp/provision/40-aws-vault.sh'
	limactl shell '$(INSTANCE)' -- zsh -lc 'bash /tmp/provision/50-starship.sh'
	limactl shell '$(INSTANCE)' -- zsh -lc 'bash /tmp/provision/60-sheldon.sh'
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
