#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Codex SDD layer: directories, sync script, wrappers, shims, and PATH registration.

.DESCRIPTION
    Deploys sync-opencode-sdd.py, writes codex-sdd-sync and codex-sdd PS1/CMD wrappers to
    launcher-dir, registers launcher-dir on the user PATH, and optionally runs the sync.

    Requires that opencode.json already exists (run `opencode` at least once first).
    Requires Python (python3 or python) on PATH.

    Foundation libraries are resolved via $env:AGENT_STACK_LIB if set, otherwise falls back
    to the fixed path: /home/tribalcode/Documents/personal/agent-stack/lib
    NOTE: The fixed fallback path is machine-specific. Set $env:AGENT_STACK_LIB for
          cross-machine portability.

.PARAMETER DryRun
    Print each mutation as a [dry-run] line. No filesystem changes, no PATH modifications,
    no sync invocations. Sets $env:DRY_RUN='1' so Invoke-AgentRun also gates.

.PARAMETER NoSync
    Skip all sync invocations (--ensure-mcps, default sync, --mcp-audit). Directory creation,
    file copy, and wrapper installation still run.

.PARAMETER SkipMcp
    Skip the --mcp-audit sync step. Other sync steps still run unless -NoSync is also set.

.PARAMETER UpdateGentle
    Run `gentle-ai upgrade` and `gentle-ai sync` before the main installation steps.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoSync,
    [switch]$SkipMcp,
    [switch]$UpdateGentle
)

$ErrorActionPreference = 'Stop'

if ($DryRun) {
    $env:DRY_RUN = '1'
}

# ---------------------------------------------------------------------------
# Resolve + dot-source foundation libraries (D8)
# ---------------------------------------------------------------------------
$libDir = if ($env:AGENT_STACK_LIB) {
    $env:AGENT_STACK_LIB
} else {
    # Fixed fallback — machine-specific; set $env:AGENT_STACK_LIB for portability
    '/home/tribalcode/Documents/personal/agent-stack/lib'
}

$platformLib = Join-Path $libDir 'platform-windows.ps1'
$commonLib   = Join-Path $libDir 'common.ps1'

if (-not (Test-Path $platformLib)) {
    throw "Foundation library not found: $platformLib. Set `$env:AGENT_STACK_LIB to the correct lib directory."
}
if (-not (Test-Path $commonLib)) {
    throw "Foundation library not found: $commonLib. Set `$env:AGENT_STACK_LIB to the correct lib directory."
}

. $platformLib
. $commonLib

# ---------------------------------------------------------------------------
# Python probe
# ---------------------------------------------------------------------------
$py = (Get-Command python3 -ErrorAction SilentlyContinue)?.Source
if (-not $py) {
    $py = (Get-Command python -ErrorAction SilentlyContinue)?.Source
}
if (-not $py) {
    Write-Error 'Python not found. Install Python 3 and ensure python3 or python is on PATH, then re-run.'
    exit 1
}

# ---------------------------------------------------------------------------
# Precondition: opencode.json must exist
# ---------------------------------------------------------------------------
$ocJson = Join-Path (Get-AgentStackPath 'opencode-config') 'opencode.json'
if (-not (Test-Path $ocJson)) {
    Write-Error @"
opencode.json not found at: $ocJson
Run `opencode` at least once to generate the configuration file, then re-run this installer.
"@
    exit 1
}

# ---------------------------------------------------------------------------
# Precondition: sync script source must exist in this repo
# ---------------------------------------------------------------------------
$syncSrc = Join-Path $PSScriptRoot 'files\sync-opencode-sdd.py'
if (-not (Test-Path $syncSrc)) {
    Write-Error "Sync script not found: $syncSrc. Ensure you are running install.ps1 from the repo root."
    exit 1
}

# ---------------------------------------------------------------------------
# Optional: update gentle-ai before installing
# ---------------------------------------------------------------------------
if ($UpdateGentle) {
    Invoke-AgentRun gentle-ai upgrade
    Invoke-AgentRun gentle-ai sync
}

# ---------------------------------------------------------------------------
# Directory creation (idempotent)
# ---------------------------------------------------------------------------
$dirs = @(
    (Join-Path (Get-AgentStackPath 'codex-root') 'scripts'),
    (Join-Path (Get-AgentStackPath 'codex-root') 'agents'),
    (Join-Path (Get-AgentStackPath 'codex-root') 'prompts'),
    (Get-AgentStackPath 'agents-skills'),
    (Get-AgentStackPath 'launcher-dir')
)

foreach ($dir in $dirs) {
    if ($DryRun) {
        Write-Host "[dry-run] New-Item -ItemType Directory -Force -Path $dir"
    } else {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Copy sync script to codex-root\scripts
# ---------------------------------------------------------------------------
$syncDest = Join-Path (Get-AgentStackPath 'codex-root') 'scripts'
if ($DryRun) {
    Write-Host "[dry-run] Copy-Item $syncSrc -> $syncDest"
} else {
    Copy-Item $syncSrc $syncDest
}

# ---------------------------------------------------------------------------
# Write wrappers and shims to launcher-dir
# ---------------------------------------------------------------------------
$launcherDir = Get-AgentStackPath 'launcher-dir'

# codex-sdd-sync.ps1
$codexSddSyncPs1 = Join-Path $launcherDir 'codex-sdd-sync.ps1'
$codexSddSyncPs1Content = '& python "$env:USERPROFILE\.codex\scripts\sync-opencode-sdd.py" @args'
if ($DryRun) {
    Write-Host "[dry-run] Write $codexSddSyncPs1"
} else {
    Set-Content -Path $codexSddSyncPs1 -Value $codexSddSyncPs1Content -Encoding UTF8
}

# codex-sdd-sync.cmd
$codexSddSyncCmd = Join-Path $launcherDir 'codex-sdd-sync.cmd'
$codexSddSyncCmdContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-sdd-sync.ps1" %*
"@
if ($DryRun) {
    Write-Host "[dry-run] Write $codexSddSyncCmd"
} else {
    Set-Content -Path $codexSddSyncCmd -Value $codexSddSyncCmdContent -Encoding ASCII
}

# codex-sdd.ps1
$codexSddPs1 = Join-Path $launcherDir 'codex-sdd.ps1'
$codexSddPs1Content = '& codex -p sdd @args'
if ($DryRun) {
    Write-Host "[dry-run] Write $codexSddPs1"
} else {
    Set-Content -Path $codexSddPs1 -Value $codexSddPs1Content -Encoding UTF8
}

# codex-sdd.cmd
$codexSddCmd = Join-Path $launcherDir 'codex-sdd.cmd'
$codexSddCmdContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-sdd.ps1" %*
"@
if ($DryRun) {
    Write-Host "[dry-run] Write $codexSddCmd"
} else {
    Set-Content -Path $codexSddCmd -Value $codexSddCmdContent -Encoding ASCII
}

# ---------------------------------------------------------------------------
# Register launcher-dir on user PATH (idempotent)
# ---------------------------------------------------------------------------
if ($DryRun) {
    Write-Host "[dry-run] Install-PathShim"
} else {
    Install-PathShim
}

# ---------------------------------------------------------------------------
# Run sync steps (unless -NoSync)
# ---------------------------------------------------------------------------
$syncScript = Join-Path (Get-AgentStackPath 'codex-root') 'scripts\sync-opencode-sdd.py'

if (-not $NoSync) {
    if ($DryRun) {
        Write-Host "[dry-run] Invoke-AgentRun $py $syncScript --ensure-mcps"
        Write-Host "[dry-run] Invoke-AgentRun $py $syncScript"
        if (-not $SkipMcp) {
            Write-Host "[dry-run] Invoke-AgentRun $py $syncScript --mcp-audit"
        }
    } else {
        Invoke-AgentRun $py $syncScript --ensure-mcps
        Invoke-AgentRun $py $syncScript
        if (-not $SkipMcp) {
            Invoke-AgentRun $py $syncScript --mcp-audit
        }
    }
}

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Codex SDD layer installed successfully.'
Write-Host "  Wrappers in : $launcherDir"
Write-Host '  Installed   : codex-sdd-sync.ps1  codex-sdd-sync.cmd'
Write-Host '                codex-sdd.ps1        codex-sdd.cmd'
Write-Host "  Sync script : $(Join-Path (Get-AgentStackPath 'codex-root') 'scripts\sync-opencode-sdd.py')"
Write-Host ''
Write-Host 'Restart your terminal session so the PATH change takes effect.'
