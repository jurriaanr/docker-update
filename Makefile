all: both

.PHONY: both
both:
	./Update-DockerImages.ps1 -Tool php
	./Update-DockerImages.ps1 -Tool apache

.PHONY: php
php:
	./Update-DockerImages.ps1 -Tool php

.PHONY: apache
apache:
	./Update-DockerImages.ps1 -Tool php

.PHONY: auto
auto:
	./Update-DockerImages.ps1 -Auto

.PHONY: dry-run
dry-run:
	./Update-DockerImages.ps1 -Auto -NoPush
