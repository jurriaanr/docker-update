# Update-DockerImages

A PowerShell script that builds and pushes the custom docker images in this repo (`jurriaanr/php`, `jurriaanr/apache`, `jurriaanr/caddy`, `jurriaanr/nginx`, `jurriaanr/frankenphp`, `jurriaanr/frankenphp-worker`) in one pass.

Cross-platform via PowerShell 7+ (`pwsh`), works on Linux, macOS, and Windows.

## What it does

For each tool, the script scans `~/sites/docker-<tool>/` for version folders, builds every folder as a local image, tags it for Docker Hub, and pushes it. The highest version per tool also gets tagged as `latest`.

## Folder convention

Each tool has its own parent directory containing one subfolder per version:

```
~/sites/docker-php/
├── php81/
├── php82/
├── php83/
├── php84/
└── php85/

~/sites/docker-apache/
└── apache24/

~/sites/docker-caddy/
└── caddy2/

~/sites/docker-nginx/
└── nginx127/

~/sites/docker-frankenphp/
└── frankenphp85/

~/sites/docker-frankenphp-worker/
└── frankenphp-worker85/
```

Folder naming: `<tool><digits>`. The digits are split into a dotted version (first digit + `.` + rest), so `php85` → `8.5`, `nginx127` → `1.27`, `caddy2` → `2`. Each folder must contain a `Dockerfile` at its root.

## Tag scheme

| Tool | Version folder | Produced tag |
|---|---|---|
| `php` | `php85` | `jurriaanr/php:8.5-fpm` |
| `apache` | `apache24` | `jurriaanr/apache:2.4-fpm` |
| `caddy` | `caddy2` | `jurriaanr/caddy:2` |
| `nginx` | `nginx127` | `jurriaanr/nginx:1.27` |
| `frankenphp` | `frankenphp85` | `jurriaanr/frankenphp:8.5` |
| `frankenphp-worker` | `frankenphp-worker85` | `jurriaanr/frankenphp-worker:8.5` |

The `-fpm` suffix applies to `php` and `apache` only (historical convention). The highest version folder per tool additionally gets a `:latest` tag.

## Usage

### Interactive

```bash
./Update-DockerImages.ps1
```

Prompts for which tool to build, lists version folders found, and lets you pick which to build (or `all`). Default when there's only one folder is to build it without prompting.

### Single tool

```bash
./Update-DockerImages.ps1 -Tool php
./Update-DockerImages.ps1 -Tool caddy
./Update-DockerImages.ps1 -Tool frankenphp-worker
```

Skips the tool prompt but still prompts for version selection if multiple folders exist.

### Build without pushing

```bash
./Update-DockerImages.ps1 -Tool php -NoPush
```

Useful when testing a local change before publishing. Also bypasses the docker-login check, so you can build without being authenticated.

### Fully automatic

```bash
./Update-DockerImages.ps1 -Auto
```

Builds **all tools**, **all versions**, pushes everything, no prompts. Output is redirected to a timestamped log file under `./logs/`. A one-line pass/fail summary prints to the console after completion.

Combine with `-NoPush` for a dry-run that exercises the build pipeline without publishing:

```bash
./Update-DockerImages.ps1 -Auto -NoPush
```

### Custom log path

```bash
./Update-DockerImages.ps1 -Auto -LogFile ~/logs/docker-update.log
```

`-LogFile` is only respected with `-Auto`. Parent directories are created if missing.

## Docker Hub login

Before pushing, the script runs `docker info` to check for an authenticated session. If not logged in, it prints:

```
! You do not appear to be logged in to Docker Hub.
    Run: docker login -u jurriaanr
```

...and aborts. Use `-NoPush` to skip the login check.

## Behavior on errors

- A failed build within a tool aborts remaining builds **for that tool**
- In `-Auto` mode, failure in one tool doesn't prevent the next tool from running
- Exit code is `0` on all-success, `1` if any build failed
- Summary at the end lists each attempted build with its status

## Partial setups

Not every machine needs every tool. If `~/sites/docker-<tool>/` doesn't exist, or exists but contains no valid version folders, that tool is silently skipped:

- In interactive mode (`-Tool nginx` when no nginx folder exists), a warning is shown and the script exits 0
- In `-Auto` mode, missing tools are logged as skipped but don't fail the overall run
- The final summary counts skipped tools separately from failures

This means `-Auto` runs cleanly on any machine with at least one tool configured, and you don't need to maintain machine-specific variations of the script.

## Makefile integration

The typical workflow integrates via a simple Makefile:

```makefile
update:
	@./Update-DockerImages.ps1

dry-run:
	@echo "This will still update local images"
	@for i in 10 9 8 7 6 5 4 3 2 1; do printf "\r%2d..." $$i; sleep 1; done; echo ""
	@./Update-DockerImages.ps1 -Auto -NoPush

auto:
	@./Update-DockerImages.ps1 -Auto
```

## Requirements

- PowerShell 7+ (`pwsh`) — the script uses three-argument `Join-Path` is avoided for compatibility, but array-based operators require 7+
- Docker CLI on the `$PATH`
- Docker daemon running
- Docker Hub account authenticated for pushes

## Script internals

Key functions:

- `Get-ToolFolders` — scans `~/sites/docker-<tool>/` and returns version folder metadata sorted by version
- `Invoke-ToolBuild` — builds and pushes all (or selected) versions of a single tool
- `Invoke-Step` — wraps individual docker commands, captures exit codes, pipes output through `Out-Host` so it doesn't pollute function returns
- `Test-DockerLogin` — parses `docker info` output for a `Username:` line

Transcript logging in `-Auto` mode uses `Start-Transcript` / `Stop-Transcript`, which captures everything written to the host including docker's build output.