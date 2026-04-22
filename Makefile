all: update

.PHONY: update
update:
	@./Update-DockerImages.ps1

.PHONY: php
php:
	@./Update-DockerImages.ps1 -Tool php

.PHONY: apache
apache:
	@./Update-DockerImages.ps1 -Tool apache

.PHONY: nginx
nginx:
	@./Update-DockerImages.ps1 -Tool nginx

.PHONY: caddy
caddy:
	@./Update-DockerImages.ps1 -Tool caddy

.PHONY: frankenphp
frankenphp:
	@./Update-DockerImages.ps1 -Tool frankenphp

.PHONY: frankenphp-worker
frankenphp-worker:
	@./Update-DockerImages.ps1 -Tool frankenphp-worker

.PHONY: auto
auto:
	@./Update-DockerImages.ps1 -Auto

.PHONY: dry-run
dry-run:
	@echo "This will still update local images"
	@for i in 10 9 8 7 6 5 4 3 2 1; do printf "\r%2d..." $$i; sleep 1; done; echo ""
	@./Update-DockerImages.ps1 -Auto -NoPush
