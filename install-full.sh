#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
NO_SYNC=0
SKIP_GENTLE=0
SKIP_OPENCODE=0
INSTALL_CODEX_CLI=0
PREFIX="${HOME}/.local/bin"
GENTLE_AGENTS="opencode,codex"
GENTLE_PRESET="full-gentleman"
GENTLE_COMPONENTS="context7,persona,engram,gga,permissions,sdd,skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="unknown"

usage() {
  cat <<'EOF'
Usage: ./install-full.sh [options]

Bootstraps a full Gentle AI/OpenCode -> Codex SDD setup from this repo.

Supported platforms:
  - macOS
  - Linux
  - WSL2

Native Windows shells are detected and stopped with WSL2 guidance.

Options:
  --dry-run             Show actions without writing files or running installers
  --yes, -y             Do not prompt before safe bootstrap actions
  --prefix DIR          Install wrapper commands into DIR (default: ~/.local/bin)
  --no-sync             Install scripts only; do not run initial Codex sync
  --skip-gentle         Do not install/run gentle-ai
  --skip-opencode       Do not install/run OpenCode
  --install-codex-cli   If codex CLI is missing, install @openai/codex with npm
  --gentle-agents LIST  Agents passed to gentle-ai install (default: opencode,codex)
  --gentle-preset NAME  Preset passed to gentle-ai install (default: full-gentleman)
  --gentle-components LIST
                        Components passed to gentle-ai install
                        (default: context7,persona,engram,gga,permissions,sdd,skills)
  -h, --help            Show help

What this does:
  1. Detects macOS/Linux/WSL2 and rejects native Windows.
  2. Ensures bootstrap prerequisites such as curl and python3 when possible.
  3. Installs OpenCode and gentle-ai when missing, with confirmation unless --yes.
  4. Runs gentle-ai upgrade/install/sync for the full opencode+codex ecosystem.
  5. Ensures ~/.config/opencode/opencode.json exists.
  6. Delegates Codex SDD compatibility installation and MCP assurance to ./install.sh.
  7. Runs sync/validation and prints Codex Desktop/CLI next steps.
EOF
}

say() { printf '[codex-sdd-full] %s\n' "$*"; }
warn() { printf '[codex-sdd-full] warning: %s\n' "$*" >&2; }
die() { printf '[codex-sdd-full] error: %s\n' "$*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_shell() {
  local command="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] bash -c %q\n' "$command"
  else
    bash -c "$command"
  fi
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    warn "non-interactive shell; rerun with --yes to approve: $prompt"
    return 1
  fi
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]
}

append_bootstrap_path() {
  export PATH="${HOME}/.local/bin:${HOME}/.opencode/bin:${HOME}/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
}

detect_platform() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || true)"
  case "$uname_s" in
    Darwin)
      PLATFORM="macos"
      ;;
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        PLATFORM="wsl2"
      else
        PLATFORM="linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      die "native Windows shell detected. Use WSL2 for now, then rerun this installer inside Ubuntu/WSL."
      ;;
    *)
      die "unsupported platform: ${uname_s:-unknown}. Supported: macOS, Linux, WSL2."
      ;;
  esac
  say "platform detected: $PLATFORM"
}

install_package() {
  local package="$1"
  case "$PLATFORM" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        confirm "Install $package using Homebrew?" || die "$package is required"
        run brew install "$package"
      else
        die "$package is required. Install Homebrew or install $package manually, then rerun."
      fi
      ;;
    linux|wsl2)
      if command -v apt-get >/dev/null 2>&1; then
        confirm "Install $package using apt-get with sudo?" || die "$package is required"
        run sudo apt-get update
        run sudo apt-get install -y "$package"
      elif command -v dnf >/dev/null 2>&1; then
        confirm "Install $package using dnf with sudo?" || die "$package is required"
        run sudo dnf install -y "$package"
      elif command -v pacman >/dev/null 2>&1; then
        if [[ "$package" == "python3" ]]; then
          package="python"
        fi
        confirm "Install $package using pacman with sudo?" || die "$package is required"
        run sudo pacman -Sy --needed "$package"
      else
        die "$package is required and no supported package manager was found. Install it manually, then rerun."
      fi
      ;;
  esac
}

ensure_command() {
  local command="$1"
  local package="${2:-$1}"
  if command -v "$command" >/dev/null 2>&1; then
    say "found $command: $(command -v "$command")"
    return 0
  fi
  warn "missing required command: $command"
  install_package "$package"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  append_bootstrap_path
  command -v "$command" >/dev/null 2>&1 || die "still missing $command after install attempt"
}

ensure_prerequisites() {
  ensure_command git git
  ensure_command curl curl
  ensure_command python3 python3
  if ! command -v python3.11 >/dev/null 2>&1; then
    warn "python3.11 not found; TOML validation will be skipped unless installed later"
    warn "to install python3.11: brew install python@3.11 (macOS) or your distro package manager"
  fi
}

install_opencode_if_needed() {
  if [[ "$SKIP_OPENCODE" == "1" ]]; then
    warn "skipping OpenCode install by request"
    return 0
  fi
  if command -v opencode >/dev/null 2>&1; then
    say "found opencode: $(command -v opencode)"
    return 0
  fi
  confirm "Install OpenCode using https://opencode.ai/install ?" || die "OpenCode is required"
  run_shell 'curl -fsSL https://opencode.ai/install | bash'
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  append_bootstrap_path
  command -v opencode >/dev/null 2>&1 || warn "opencode not found in PATH after installer; you may need to restart your shell"
}

install_gentle_if_needed() {
  if [[ "$SKIP_GENTLE" == "1" ]]; then
    warn "skipping gentle-ai install by request"
    return 0
  fi
  if command -v gentle-ai >/dev/null 2>&1; then
    say "found gentle-ai: $(command -v gentle-ai)"
    return 0
  fi
  confirm "Install Gentle AI from the official Gentleman-Programming installer ?" || die "gentle-ai is required"
  run_shell 'curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash'
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  append_bootstrap_path
  command -v gentle-ai >/dev/null 2>&1 || die "gentle-ai not found in PATH after install"
}

ensure_codex_cli_optional() {
  if command -v codex >/dev/null 2>&1; then
    say "found codex CLI: $(command -v codex)"
    return 0
  fi
  if [[ "$INSTALL_CODEX_CLI" != "1" ]]; then
    warn "codex CLI not found. This is OK for Codex Desktop, but CLI users should install Codex or rerun with --install-codex-cli."
    return 0
  fi
  command -v npm >/dev/null 2>&1 || die "npm is required for --install-codex-cli"
  confirm "Install @openai/codex globally with npm?" || die "codex CLI install skipped"
  run npm install -g @openai/codex
}

run_gentle_setup() {
  if [[ "$SKIP_GENTLE" == "1" ]]; then
    return 0
  fi
  command -v gentle-ai >/dev/null 2>&1 || die "gentle-ai is not available"
  say "updating Gentle AI managed tools"
  run gentle-ai upgrade
  say "running gentle-ai install for agents=${GENTLE_AGENTS}, preset=${GENTLE_PRESET}, components=${GENTLE_COMPONENTS}"
  say "this may be interactive if gentle-ai needs confirmation or provider setup"
  local args=(install --agents "$GENTLE_AGENTS" --preset "$GENTLE_PRESET")
  if [[ -n "$GENTLE_COMPONENTS" ]]; then
    args+=(--components "$GENTLE_COMPONENTS")
  fi
  run gentle-ai "${args[@]}"
  say "running gentle-ai sync"
  run gentle-ai sync
}

ensure_opencode_config() {
  local config="${HOME}/.config/opencode/opencode.json"
  if [[ -f "$config" ]]; then
    say "OpenCode config exists: $config"
    return 0
  fi

  warn "missing OpenCode config: $config"
  if [[ "$DRY_RUN" == "1" ]]; then
    say "would require OpenCode config before running compatibility sync"
    return 0
  fi
  if [[ "$SKIP_OPENCODE" == "1" ]]; then
    die "OpenCode config is required; rerun without --skip-opencode after configuring OpenCode"
  fi

  if command -v opencode >/dev/null 2>&1 && confirm "Open OpenCode now so you can complete provider/config setup?"; then
    run opencode
  else
    die "Run 'opencode' once, complete configuration, then rerun ./install-full.sh"
  fi

  [[ -f "$config" ]] || die "OpenCode config still missing after running opencode: $config"
}

install_codex_sdd_layer() {
  [[ -x "${SCRIPT_DIR}/install.sh" ]] || die "missing executable install.sh next to install-full.sh"
  local args=(--prefix "$PREFIX")
  if [[ "$NO_SYNC" == "1" ]]; then
    args+=(--no-sync)
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    args+=(--dry-run)
  fi
  say "installing Codex SDD compatibility layer"
  run "${SCRIPT_DIR}/install.sh" "${args[@]}"
}

validate_install() {
  if [[ "$NO_SYNC" == "1" ]]; then
    warn "skipping sync validation because --no-sync was provided"
    return 0
  fi
  append_bootstrap_path
  if command -v codex-sdd-sync >/dev/null 2>&1; then
    say "running codex-sdd-sync"
    run codex-sdd-sync
    say "checking Codex SDD sync drift"
    run codex-sdd-sync --check
  else
    warn "codex-sdd-sync not found in PATH; try restarting the shell or run ~/.local/bin/codex-sdd-sync"
  fi

  if command -v python3.11 >/dev/null 2>&1; then
    say "running Python 3.11 validation"
    run python3.11 "${HOME}/.codex/scripts/sync-opencode-sdd.py" --test
  else
    warn "python3.11 not found; skipped TOML validation. To install: brew install python@3.11 (macOS) or your distro package manager."
  fi
}

print_next_steps() {
  cat <<EOF

[codex-sdd-full] Done.

Next steps:
  1. Restart Codex Desktop/CLI if it was already open.
  2. Open your project directory in Codex.
  3. Type:
       sdd init
       sdd auto my-change

CLI users can also run:
  cd /path/to/project
  codex-sdd

If you update Gentle AI/OpenCode later:
  ./install.sh --update-gentle

If agent-stack or other tools are not found, add ~/.local/bin to your PATH (zsh):
  export PATH="$HOME/.local/bin:$PATH"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --prefix) PREFIX="${2:?--prefix requires a directory}"; shift ;;
    --no-sync) NO_SYNC=1 ;;
    --skip-gentle) SKIP_GENTLE=1 ;;
    --skip-opencode) SKIP_OPENCODE=1 ;;
    --install-codex-cli) INSTALL_CODEX_CLI=1 ;;
    --gentle-agents) GENTLE_AGENTS="${2:?--gentle-agents requires a comma-separated list}"; shift ;;
    --gentle-preset) GENTLE_PRESET="${2:?--gentle-preset requires a preset name}"; shift ;;
    --gentle-components) GENTLE_COMPONENTS="${2:?--gentle-components requires a comma-separated list}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

append_bootstrap_path
detect_platform
ensure_prerequisites
install_opencode_if_needed
install_gentle_if_needed
ensure_codex_cli_optional
run_gentle_setup
ensure_opencode_config
install_codex_sdd_layer
validate_install
print_next_steps
