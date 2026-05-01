#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
NO_SYNC=0
PREFIX="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Installs the Codex compatibility layer for gentle-ai/OpenCode SDD workflows.

Options:
  --dry-run        Show actions without writing files
  --no-sync        Install scripts only; do not run initial sync
  --prefix DIR     Install wrapper command into DIR (default: ~/.local/bin)
  -h, --help       Show help

Requirements:
  - Codex installed/configured at ~/.codex
  - gentle-ai/OpenCode installed/configured at ~/.config/opencode/opencode.json
  - python3 for sync
  - python3.11 recommended for TOML validation tests
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-sync) NO_SYNC=1 ;;
    --prefix) PREFIX="${2:?--prefix requires a directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

say() { printf '[codex-sdd] %s\n' "$*"; }
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}
install_file() {
  local src="$1" dst="$2" mode="${3:-0644}"
  if [[ "$DRY_RUN" == "1" ]]; then
    say "would install $src -> $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    say "unchanged $dst"
  else
    install -m "$mode" "$src" "$dst"
    say "installed $dst"
  fi
}
write_wrapper() {
  local dst="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    say "would write $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cat > "$dst" <<EOF
#!/usr/bin/env bash
set -euo pipefail
python3 "${HOME}/.codex/scripts/sync-opencode-sdd.py" "\$@"
EOF
  chmod +x "$dst"
  say "installed $dst"
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing required command: python3" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  say "warning: codex command not found in PATH. Continue only if Codex Desktop/CLI is installed separately."
fi

if [[ ! -f "${HOME}/.config/opencode/opencode.json" ]]; then
  echo "Missing ${HOME}/.config/opencode/opencode.json" >&2
  echo "Install gentle-ai/OpenCode first, then rerun this installer." >&2
  exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/files/sync-opencode-sdd.py" ]]; then
  echo "Installer is incomplete: missing files/sync-opencode-sdd.py" >&2
  exit 1
fi

run mkdir -p "${HOME}/.codex/scripts" "${HOME}/.codex/agents" "${HOME}/.codex/prompts" "${HOME}/.agents/skills" "$PREFIX"
install_file "${SCRIPT_DIR}/files/sync-opencode-sdd.py" "${HOME}/.codex/scripts/sync-opencode-sdd.py" 0755
write_wrapper "${PREFIX}/codex-sdd-sync"

if [[ "$NO_SYNC" != "1" ]]; then
  say "running initial OpenCode -> Codex sync"
  run python3 "${HOME}/.codex/scripts/sync-opencode-sdd.py"
  if command -v python3.11 >/dev/null 2>&1; then
    say "running validation test with python3.11"
    run python3.11 "${HOME}/.codex/scripts/sync-opencode-sdd.py" --test
  else
    say "python3.11 not found; skipping TOML validation. Install python3.11 and run: python3.11 ~/.codex/scripts/sync-opencode-sdd.py --test"
  fi
fi

say "installed. Restart Codex CLI/Desktop if already running."
say "try in Codex: sdd init | sdd-new my-change | sdd auto my-change"
