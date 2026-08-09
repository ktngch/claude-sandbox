INSTANCE ?= claude-code
TEMPLATE  := lima/claude-code.yaml
PROVISION := lima/provision

.DEFAULT_GOAL := up
.PHONY: up claude shell reprovision recreate stop destroy status validate ssh-config help

## up: VM を作成 (初回のみ) して起動し、プロビジョニングを流す
up:
	@if limactl list -q 2>/dev/null | grep -qx '$(INSTANCE)'; then \
		echo '==> starting existing instance: $(INSTANCE)'; \
		limactl start '$(INSTANCE)'; \
	else \
		echo '==> creating instance from $(TEMPLATE) (初回は 10 分程度かかります)'; \
		limactl start --name='$(INSTANCE)' '$(TEMPLATE)' --progress --timeout=20m -y; \
	fi

## claude: VM 内の ~/workspace で claude を起動する
#
# --dangerously-skip-permissions を付けているのは、この VM が完全隔離 (mounts: []) で
# ホストのファイルシステム・認証情報に到達する経路を持たないため。
# lima/claude-code.yaml に mounts を足すと、この前提が崩れる。
claude: up
	limactl shell '$(INSTANCE)' -- bash -lc 'cd ~/workspace && exec claude --dangerously-skip-permissions'

## shell: VM にログインする
shell: up
	limactl shell '$(INSTANCE)'

## reprovision: provision/ 配下のスクリプトだけを再適用する (VM は作り直さない)
reprovision:
	limactl copy -r '$(PROVISION)' '$(INSTANCE):/tmp/'
	limactl shell '$(INSTANCE)' -- sudo bash /tmp/provision/00-system-packages.sh
	limactl shell '$(INSTANCE)' -- bash -lc 'install -D -m 0644 /tmp/provision/mise.toml ~/.config/mise/config.toml'
	limactl shell '$(INSTANCE)' -- bash -lc 'bash /tmp/provision/10-mise.sh'
	limactl shell '$(INSTANCE)' -- bash -lc 'bash /tmp/provision/20-dev-env.sh'

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
