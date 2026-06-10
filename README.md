# Codex SDD Gentle Installer

Installs the Codex compatibility layer for the gentle-ai/OpenCode SDD workflow.

## Full bootstrap for a new machine

Use this when a teammate starts with only Git and needs the complete local setup.

```bash
git clone https://github.com/SoyJohnXD/codex-sdd-gentle-installer.git
cd codex-sdd-gentle-installer
./install-full.sh
```

The full bootstrap installer:

1. Detects macOS, Linux, or WSL2.
2. Rejects native Windows shells with WSL2 guidance.
3. Ensures `curl` and `python3` are available when possible.
4. Installs OpenCode and Gentle AI if missing, with confirmation.
5. Updates Gentle AI managed tools and runs deterministic Gentle AI setup for the full OpenCode + Codex ecosystem:
   `gentle-ai install --agents opencode,codex --preset full-gentleman --components context7,persona,engram,gga,permissions,sdd,skills`,
   then `gentle-ai sync`.
6. Verifies `~/.config/opencode/opencode.json`.
7. Delegates to this repo's `./install.sh`, which ensures Codex MCP config for Engram and Context7.
8. Runs Codex SDD sync/validation when possible.

Supported full-bootstrap platforms:

| Platform | Status | Notes |
| --- | --- | --- |
| macOS | Supported | Recommended for Codex Desktop users. Restart Codex Desktop after install. |
| Linux | Supported | Works for CLI-oriented setup. |
| WSL2 | Supported | Recommended Windows path. |
| Native Windows | ✅ | `powershell -ExecutionPolicy Bypass -File install-full.ps1` |

## Windows install

```powershell
# Prerequisites: Git, Python 3, PowerShell 5.1+
# Requires $env:AGENT_STACK_LIB pointing to agent-stack/lib (set by agent-stack bootstrap)

# Full bootstrap (installs OpenCode, gentle-ai, Codex SDD layer):
powershell -ExecutionPolicy Bypass -File install-full.ps1

# SDD layer only (if OpenCode and gentle-ai already installed):
powershell -ExecutionPolicy Bypass -File install.ps1
```

OpenCode is installed via winget → scoop → choco (first available). If none are present, the script prints the manual download URL.

Useful options:

```bash
./install-full.sh --dry-run
./install-full.sh --yes
./install-full.sh --install-codex-cli
./install-full.sh --prefix ~/.local/bin
./install-full.sh --gentle-agents opencode,codex
./install-full.sh --gentle-components context7,persona,engram,gga,permissions,sdd,skills
```

See the PRD: [`docs/full-bootstrap-installer-prd.md`](docs/full-bootstrap-installer-prd.md).

## Install order

1. Install Codex CLI/Desktop.
2. Install gentle-ai/OpenCode and let it create `~/.config/opencode/opencode.json`.
3. Run this installer:

```bash
./install.sh
```

Restart Codex after installation.

## One-command updater

Use this after updating Codex, OpenCode, Gentle AI, or this repository:

```bash
./install.sh --update-gentle
```

This runs the complete local update flow:

1. `gentle-ai upgrade`
2. `gentle-ai sync`
3. Ensure Codex MCP config for Engram and Context7
4. Regenerate Codex SDD agents/prompts/instructions
5. Validate the generated Codex SDD configuration

## What it installs

- `~/.codex/scripts/sync-opencode-sdd.py`
- `~/.local/bin/codex-sdd-sync`
- `~/.local/bin/codex-sdd` — opens Codex with the dedicated SDD profile
- generated Codex SDD agents under `~/.codex/agents/sdd-*.toml`
- generated prompts under `~/.codex/prompts/sdd-*.md`
- workflow/sync instructions in `~/.codex/engram-instructions.md` and `~/.codex/AGENTS.override.md`
- skill discovery symlinks under `~/.agents/skills`
- Codex MCP config entries in `~/.codex/config.toml` for:
  - `engram` — persistent memory and SDD artifact storage
  - `context7` — current developer documentation lookup

## After updating gentle-ai/OpenCode

Run:

```bash
./install.sh --update-gentle
```

Or tell Codex: “actualicé OpenCode/gentle-ai, sincronízate”.

Why the order matters: recent Gentle AI versions regenerate persona/skill blocks
and may change OpenCode's internal SDD agent names during `gentle-ai sync`.
`codex-sdd-sync` must run after that so Codex receives the refreshed prompts,
skills, and the local `sdd-orchestrator` compatibility agent.

## MCP audit and repair

The updater preserves existing user-managed MCP blocks and only appends missing
required blocks. To inspect or repair MCP config directly:

```bash
codex-sdd-sync --mcp-audit
codex-sdd-sync --ensure-mcps
codex mcp list
```

Expected core MCPs:

| MCP | Purpose | Configured command |
| --- | --- | --- |
| `engram` | Memory and SDD artifacts | `engram mcp --tools=agent` |
| `context7` | Current developer docs | `npx -y @upstash/context7-mcp` |

## Open an SDD session

From your project directory:

```bash
codex-sdd
```

This is equivalent to:

```bash
codex -p sdd
```

The Codex UI may still display the visible agent as `main`; that is expected. The `sdd` profile makes the main session behave as the SDD orchestrator and delegate phase work to subagents.

## SDD commands in Codex

Use text commands if slash prompts do not appear:

```txt
sdd init
sdd-new my-change
sdd ff my-change
sdd apply my-change
sdd verify my-change
sdd archive my-change
sdd auto my-change
sdd-exec my-change
ready to exec my-change
```

`auto` / `ready to exec` completes the full flow: init, missing planning, apply, verify, archive if verification passes, with one fix loop on verification failure.


## Multi-agent and Strict TDD defaults

The installer configures Codex to mirror Gentle AI/OpenCode SDD intent:

- `sdd-orchestrator` is the coordinator and should keep its own context thin.
- Non-trivial SDD work should use generated phase agents (`sdd-explore`, `sdd-propose`, `sdd-spec`, `sdd-design`, `sdd-tasks`, `sdd-apply`, `sdd-verify`, `sdd-archive`).
- Single-agent inline execution is an exception for docs-only, tiny config-only, urgent tightly-coupled hotfixes, or when the current Codex runtime blocks subagent spawning.
- Strict TDD is the default when a test runner exists and the change touches production code. In that mode, apply must produce TDD Cycle Evidence and verify must reject missing evidence.

These rules are generated into:

- `~/.codex/agents/sdd-orchestrator.toml`
- `~/.codex/agents/sdd-apply.toml`
- `~/.codex/agents/sdd-verify.toml`
- `~/.codex/sdd-profile-instructions.md`
- `~/.codex/engram-instructions.md` and `~/.codex/AGENTS.override.md`

Run `./install.sh --update-gentle` after Gentle AI/OpenCode updates to regenerate these Codex defaults.

`AGENTS.override.md` is the file Codex CLI loads first per directory (before `AGENTS.md`); the sync only
upserts its own `<!-- gentle-ai:codex-sdd-workflow -->` and `<!-- gentle-ai:codex-sync-protocol -->`
marker blocks there and leaves any other tool's marker blocks (e.g. `intent-overlay`, `persona-co`) untouched.
If either of gentle-ai's own markers is found unpaired (e.g. an orphaned start marker left by a manual
edit), the sync refuses to modify the file and reports an error asking you to repair it manually.

## Engram artifact namespace guard

Codex SDD phase agents must not rely on the implicit project selected by the Engram MCP server. The SDD profile now instructs the orchestrator to resolve `PROJECT_ROOT` and `PROJECT_NAME`, pass them to every phase, and require explicit `project: PROJECT_NAME` on Engram artifact reads/writes.

This prevents false verification failures where `sdd-verify` cannot find artifacts because an earlier phase saved `sdd/<change>/tasks` under a different Engram project namespace. If drift is detected, the workflow should classify it as `artifact_namespace_drift`, backfill/retry the artifact under the canonical project, and avoid misclassifying the issue as an implementation failure when tests and specs pass.

## Dry run

```bash
./install.sh --dry-run
```

## Share with a colleague

```bash
tar -czf codex-sdd-gentle-installer.tar.gz codex-sdd-gentle-installer
```

Colleague:

```bash
tar -xzf codex-sdd-gentle-installer.tar.gz
cd codex-sdd-gentle-installer
./install.sh
```
