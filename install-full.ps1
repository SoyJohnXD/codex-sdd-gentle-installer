#Requires -Version 5.1
<#
.SYNOPSIS
    Full end-to-end bootstrap for the Codex SDD installer on Windows.

.DESCRIPTION
    Installs all prerequisites (OpenCode, gentle-ai, optional Codex CLI), runs
    gentle-ai upgrade/sync/install, then delegates to install.ps1 for the Codex SDD
    layer installation, and finally validates the installation.

    Requires native Windows (exits immediately on non-Windows platforms).

    Foundation libraries are resolved via $env:AGENT_STACK_LIB if set, otherwise falls back
    to the fixed path: /home/tribalcode/Documents/personal/agent-stack/lib
    NOTE: The fixed fallback path is machine-specific. Set $env:AGENT_STACK_LIB for
          cross-machine portability.

.PARAMETER DryRun
    Sets $env:DRY_RUN='1' and forwards -DryRun to install.ps1. All mutations are
    reported as [dry-run] lines without executing.

.PARAMETER SkipCodex
    Skip OpenCode installation. Useful if OpenCode is already installed.

.PARAMETER InstallCodexCli
    Install @openai/codex globally via npm (requires npm on PATH).

.PARAMETER WithClaude
    Reserved for future use.

.PARAMETER Ci
    Non-interactive mode. Skip the interactive prompt to run opencode manually.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipCodex,
    [switch]$SkipMcp,
    [switch]$InstallCodexCli,
    [switch]$WithClaude,
    [switch]$Ci
)

# ---------------------------------------------------------------------------
# Windows-only guard — must be the first executable statement
# ---------------------------------------------------------------------------
if ($env:OS -ne 'Windows_NT') {
    Write-Error 'This installer runs on Windows only. On macOS/Linux use install-full.sh.'
    exit 1
}

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
# Prerequisite check (non-fatal warnings)
# ---------------------------------------------------------------------------
$missing = @()
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $missing += 'git' }

$hasPython = (Get-Command python3 -ErrorAction SilentlyContinue) -or (Get-Command python -ErrorAction SilentlyContinue)
if (-not $hasPython) { $missing += 'python3 or python' }

if ($missing.Count -gt 0) {
    Write-Warning "Missing prerequisites: $($missing -join ', '). Some steps may fail."
}

# ---------------------------------------------------------------------------
# Install OpenCode (D2: first-success chain)
# ---------------------------------------------------------------------------
if (-not $SkipCodex) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Invoke-AgentRun winget install opencode.opencode --silent
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        Invoke-AgentRun scoop install opencode
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Invoke-AgentRun choco install opencode
    } else {
        Write-Host 'No package manager found (winget, scoop, choco).'
        Write-Host 'Install OpenCode manually from: https://opencode.ai/download'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Install gentle-ai
# ---------------------------------------------------------------------------
Invoke-AgentRun powershell -NoProfile -Command "iex (irm 'https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.ps1')"

# ---------------------------------------------------------------------------
# Optional: install @openai/codex CLI
# ---------------------------------------------------------------------------
if ($InstallCodexCli -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Invoke-AgentRun npm install -g @openai/codex
}

# ---------------------------------------------------------------------------
# gentle-ai upgrade / sync / install
# ---------------------------------------------------------------------------
Invoke-AgentRun gentle-ai upgrade
Invoke-AgentRun gentle-ai sync
Invoke-AgentRun gentle-ai install

# ---------------------------------------------------------------------------
# Precondition: opencode.json — prompt user if missing
# ---------------------------------------------------------------------------
$ocJson = Join-Path (Get-AgentStackPath 'opencode-config') 'opencode.json'
if (-not (Test-Path $ocJson)) {
    Write-Host ''
    Write-Host 'opencode.json not found. Please run `opencode` at least once to generate the'
    Write-Host "configuration file at: $ocJson"
    Write-Host ''
    if (-not $Ci) {
        Read-Host 'Press Enter after running opencode once to continue...'
    } else {
        Write-Host '[-Ci mode] Skipping interactive wait. Continuing — install.ps1 will validate.'
    }
}

# ---------------------------------------------------------------------------
# Build passthrough args for install.ps1
# ---------------------------------------------------------------------------
$passThruArgs = @{}
if ($DryRun)    { $passThruArgs['DryRun']   = $true }
if ($SkipCodex) { $passThruArgs['NoSync']   = $true }
if ($SkipMcp)   { $passThruArgs['SkipMcp']  = $true }

# ---------------------------------------------------------------------------
# Delegate to install.ps1
# ---------------------------------------------------------------------------
& "$PSScriptRoot\install.ps1" @passThruArgs

# ---------------------------------------------------------------------------
# Python probe (needed for validation)
# ---------------------------------------------------------------------------
$py = (Get-Command python3 -ErrorAction SilentlyContinue)?.Source
if (-not $py) {
    $py = (Get-Command python -ErrorAction SilentlyContinue)?.Source
}
if (-not $py) {
    Write-Error 'Python not found after install. Cannot run validation step.'
    exit 1
}

# ---------------------------------------------------------------------------
# Validate installation
# ---------------------------------------------------------------------------
if (-not $DryRun) {
    $syncScript = Join-Path (Get-AgentStackPath 'codex-root') 'scripts\sync-opencode-sdd.py'
    Write-Host "Running validation: $py $syncScript --test"
    & $py $syncScript --test
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Validation failed (exit code $LASTEXITCODE). Check the output above for details."
        exit 1
    }
} else {
    Write-Host '[dry-run] Skipping --test validation'
}

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Full Codex SDD bootstrap completed successfully.'
Write-Host '  - OpenCode installed'
Write-Host '  - gentle-ai installed, upgraded, and synced'
if ($InstallCodexCli) { Write-Host '  - @openai/codex CLI installed' }
Write-Host '  - Codex SDD layer installed (wrappers, shims, PATH)'
Write-Host '  - Installation validated'
Write-Host ''
Write-Host 'Restart your terminal session so PATH changes take effect.'
