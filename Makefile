all: dry-run

.PHONY: php
php:
	./Update-DockerImages.ps1 -Tool php

.PHONY: apache
apache:
	./Update-DockerImages.ps1 -Tool apache

.PHONY: nginx
php:
	./Update-DockerImages.ps1 -Tool nginx

.PHONY: caddy
php:
	./Update-DockerImages.ps1 -Tool caddy

.PHONY: auto
auto:
	./Update-DockerImages.ps1 -Auto

.PHONY: dry-run
dry-run:
	@echo "This will still update local images"
	@for i in 10 9 8 7 6 5 4 3 2 1; do printf "\r%2d..." $$i; sleep 1; done; echo ""
	@./Update-DockerImages.ps1 -Auto -NoPush
