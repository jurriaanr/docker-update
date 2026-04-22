#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build and push Jurriaan's custom PHP / Apache docker images.

.DESCRIPTION
    Scans ~/sites/docker-<tool>/ for folders matching <tool><version-digits>
    (e.g. php85, apache24), builds each as jurriaanr/<tool>:<dotted-version>-fpm,
    and pushes to Docker Hub. The highest version per tool also gets tagged `latest`.

.PARAMETER Tool
    Which tool to update: 'php' or 'apache'. Prompts if omitted. Ignored in -Auto mode.

.PARAMETER NoPush
    Build and tag only; skip `docker push`.

.PARAMETER Auto
    Fully automatic: both tools, all versions, push, no prompts. Output goes to a log file.

.PARAMETER LogFile
    Path to the log file (only used with -Auto). Defaults to ./docker-update-<timestamp>.log.

.EXAMPLE
    ./Update-DockerImages.ps1
    ./Update-DockerImages.ps1 -Tool php
    ./Update-DockerImages.ps1 -Tool php -NoPush
    ./Update-DockerImages.ps1 -Auto
    ./Update-DockerImages.ps1 -Auto -LogFile ~/logs/docker.log
#>

[CmdletBinding()]
param(
    [ValidateSet('php', 'apache')]
    [string]$Tool,

    [switch]$NoPush,

    [switch]$Auto,

    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

# ---------- helpers ----------

function Write-Info    { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "  ✓ $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-ErrMsg  { param($m) Write-Host "  ✗ $m" -ForegroundColor Red }

function Test-DockerLogin {
    try {
        $info = docker info 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $line = $info | Select-String -Pattern '^\s*Username:\s*(.+)$'
        if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
        return $null
    } catch {
        return $null
    }
}

function ConvertTo-DottedVersion {
    # "85" -> "8.5", "24" -> "2.4", "810" -> "8.10"
    param([string]$Digits)
    if ($Digits.Length -lt 2) { return $Digits }
    return "$($Digits[0]).$($Digits.Substring(1))"
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action
    )
    Write-Host "  → $Label" -ForegroundColor DarkGray
    # Pipe to Out-Host so docker's stdout is still displayed/logged
    # but does NOT pollute the caller's pipeline (which collects results).
    & $Action | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed ($Label) with exit code $LASTEXITCODE"
    }
}

function Get-ToolFolders {
    param([string]$ToolName)

    $baseDir = Join-Path $HOME "sites/docker-$ToolName"
    if (-not (Test-Path $baseDir)) {
        Write-ErrMsg "Base directory not found: $baseDir"
        return @()
    }

    $pattern = "^$ToolName(\d{2,})$"
    return Get-ChildItem -Path $baseDir -Directory |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $digits = $_.Name -replace "^$ToolName", ''
            [pscustomobject]@{
                Name    = $_.Name
                Path    = $_.FullName
                Digits  = $digits
                Version = ConvertTo-DottedVersion $digits
                SortKey = [version](ConvertTo-DottedVersion $digits)
            }
        } |
        Sort-Object SortKey
}

function Invoke-ToolBuild {
    <#
    Build+push all (or selected) versions of one tool.
    Returns result objects: @{ Tool; Name; Status; Error }.
    In interactive mode, prompts for version selection when multiple folders exist.
    In auto mode (-InteractiveSelection:$false), builds all folders.
    #>
    param(
        [string]$ToolName,
        [bool]$InteractiveSelection,
        [bool]$DoPush
    )

    Write-Host ""
    Write-Info "Tool: $ToolName"

    $folders = Get-ToolFolders -ToolName $ToolName
    if (-not $folders -or $folders.Count -eq 0) {
        Write-ErrMsg "No version folders found for '$ToolName'; skipping."
        return @([pscustomobject]@{ Tool = $ToolName; Name = '(none)'; Status = 'skipped'; Error = 'no folders' })
    }

    Write-Info "Found $($folders.Count) version folder(s) for ${ToolName}:"
    for ($i = 0; $i -lt $folders.Count; $i++) {
        $f = $folders[$i]
        $marker = ''
        if ($i -eq $folders.Count - 1) { $marker = '  (latest)' }
        Write-Host ("    [{0}] {1}  →  {2}{3}" -f ($i + 1), $f.Name, $f.Version, $marker)
    }

    # --- selection ---
    $selected = @()
    if (-not $InteractiveSelection -or $folders.Count -eq 1) {
        $selected = $folders
    } else {
        Write-Host ""
        $selection = (Read-Host "Which to build? (comma-separated indices, or 'all')").Trim().ToLower()

        if ($selection -eq '' -or $selection -eq 'all') {
            $selected = $folders
        } else {
            $indices = $selection -split ',' | ForEach-Object { $_.Trim() }
            foreach ($idx in $indices) {
                if ($idx -notmatch '^\d+$') { Write-ErrMsg "Invalid index: '$idx'"; return @() }
                $n = [int]$idx
                if ($n -lt 1 -or $n -gt $folders.Count) { Write-ErrMsg "Index out of range: $n"; return @() }
                $selected += $folders[$n - 1]
            }
        }
    }

    if (-not $selected -or $selected.Count -eq 0) {
        Write-WarnMsg "Nothing selected for $ToolName."
        return @()
    }

    # highest version in the FULL list gets `latest`
    $latestFolder = $folders[-1]

    # --- build loop ---
    $results = @()
    foreach ($f in $selected) {
        $tagBase  = "$($f.Version)-fpm"
        $remote   = "jurriaanr/${ToolName}:$tagBase"
        $isLatest = ($f.Name -eq $latestFolder.Name)

        Write-Host ""
        Write-Info "Building $($f.Name) → $remote"

        try {
            Push-Location $f.Path

            Invoke-Step "docker image build --network=host -t $tagBase ." {
                docker image build --network=host -t $tagBase .
            }
            Invoke-Step "docker image tag $tagBase $remote" {
                docker image tag $tagBase $remote
            }
            if ($DoPush) {
                Invoke-Step "docker push $remote" {
                    docker push $remote
                }
            }

            if ($isLatest) {
                $remoteLatest = "jurriaanr/${ToolName}:latest"
                Invoke-Step "docker image tag $tagBase $remoteLatest" {
                    docker image tag $tagBase $remoteLatest
                }
                if ($DoPush) {
                    Invoke-Step "docker push $remoteLatest" {
                        docker push $remoteLatest
                    }
                }
            }

            Write-Ok "$($f.Name) done"
            $results += [pscustomobject]@{ Tool = $ToolName; Name = $f.Name; Status = 'ok'; Error = $null }
        }
        catch {
            Write-ErrMsg "$($f.Name) FAILED: $_"
            $results += [pscustomobject]@{ Tool = $ToolName; Name = $f.Name; Status = 'failed'; Error = "$_" }
            if ((Get-Location).Path -eq $f.Path) { Pop-Location }
            Write-Host ""
            Write-ErrMsg "Aborting remaining $ToolName builds."
            break
        }
        finally {
            if ((Get-Location).Path -eq $f.Path) { Pop-Location }
        }
    }

    return $results
}

# ---------- entry point ----------

# Parameter sanity: -Tool / -LogFile only make sense in their respective modes.
if ($Auto -and $Tool) {
    Write-WarnMsg "-Tool is ignored in -Auto mode (all tools are processed)."
}
if ($LogFile -and -not $Auto) {
    Write-WarnMsg "-LogFile is only used with -Auto; ignoring."
    $LogFile = $null
}

# Set up transcript logging for auto mode
$transcriptStarted = $false
if ($Auto) {
    if (-not $LogFile) {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
        $LogFile = Join-Path (Join-Path (Get-Location) 'logs') "docker-update-$stamp.log"
    }
    # Ensure parent dir exists
    $logDir = Split-Path -Parent $LogFile
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    Write-Host "Auto mode: logging to $LogFile"
    try {
        Start-Transcript -Path $LogFile -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-ErrMsg "Could not start transcript at '$LogFile': $_"
        exit 1
    }
}

$exitCode = 0
$allResults = @()

try {
    # --- pick tool (interactive mode only) ---
    if (-not $Auto -and -not $Tool) {
        Write-Host ""
        Write-Host "What do you want to update?"
        Write-Host "  1) php"
        Write-Host "  2) apache"
        $choice = (Read-Host "Choice [1/2]").Trim()
        switch ($choice) {
            '1'      { $Tool = 'php' }
            'php'    { $Tool = 'php' }
            '2'      { $Tool = 'apache' }
            'apache' { $Tool = 'apache' }
            default  { Write-ErrMsg "Invalid choice: '$choice'"; exit 1 }
        }
    }

    # --- docker login check ---
    $loggedInAs = Test-DockerLogin
    if (-not $loggedInAs) {
        Write-WarnMsg "You do not appear to be logged in to Docker Hub."
        Write-Host "    Run: docker login -u jurriaanr" -ForegroundColor Yellow
        if (-not $NoPush) {
            Write-ErrMsg "Aborting (push would fail). Re-run with -NoPush to build without pushing."
            exit 1
        }
    } else {
        Write-Ok "Logged in to Docker as '$loggedInAs'"
    }

    # --- run ---
    $doPush = -not $NoPush

    if ($Auto) {
        Write-Info "Auto mode: building all tools, all versions, pushing."
        foreach ($t in @('php', 'apache')) {
            $allResults += Invoke-ToolBuild -ToolName $t -InteractiveSelection:$false -DoPush:$doPush
        }
    } else {
        $allResults += Invoke-ToolBuild -ToolName $Tool -InteractiveSelection:$true -DoPush:$doPush
    }

    # --- summary ---
    Write-Host ""
    Write-Info "Summary"
    if (-not $allResults -or $allResults.Count -eq 0) {
        Write-WarnMsg "No builds ran."
    } else {
        foreach ($r in $allResults) {
            $label = "$($r.Tool)/$($r.Name)"
            switch ($r.Status) {
                'ok'      { Write-Ok $label }
                'skipped' { Write-WarnMsg "$label — $($r.Error)" }
                default   { Write-ErrMsg "$label — $($r.Error)" }
            }
        }
    }

    if ($NoPush) {
        Write-Host ""
        Write-WarnMsg "Push was skipped (-NoPush)."
    }

    if ($allResults | Where-Object { $_.Status -eq 'failed' }) { $exitCode = 1 }
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
        # Short summary outside the transcript so unattended callers see pass/fail
        $failed = @($allResults | Where-Object { $_.Status -eq 'failed' }).Count
        $ok     = @($allResults | Where-Object { $_.Status -eq 'ok'     }).Count
        Write-Host "Auto run complete: $ok ok, $failed failed. Log: $LogFile"
    }
}

exit $exitCode
