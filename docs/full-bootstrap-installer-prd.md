# PRD: Full Bootstrap Installer

## Problem

Teammates currently need to install and configure several pieces manually before they can use the Codex SDD workflow:

- Codex Desktop or Codex CLI
- OpenCode
- Gentle AI
- This repo's Codex SDD compatibility layer
- The OpenCode -> Codex sync validation path

The existing `install.sh` correctly installs only the compatibility layer, but it assumes OpenCode/Gentle AI configuration already exists. New users need a clearer "start with Git only" path.

## Goal

Provide a full bootstrap entrypoint that lets a teammate clone this repo and run one command to install or validate the complete local SDD setup.

```bash
git clone https://github.com/nicolasvosoria/codex-sdd-gentle-installer.git
cd codex-sdd-gentle-installer
./install-full.sh
```

After completion, the user should be able to restart Codex Desktop/CLI and type:

```txt
sdd init
sdd auto my-change
```

## Users

- **Mac Codex Desktop teammate**: already uses Codex Desktop, wants SDD commands available in the app.
- **Linux/WSL2 CLI teammate**: wants to bootstrap OpenCode/Gentle AI and use Codex CLI with `codex-sdd`.
- **Maintainer**: wants a safe, idempotent installer that delegates to the existing compatibility-layer installer.

## Scope

The full bootstrap installer should:

1. Detect supported platforms: macOS, Linux, WSL2.
2. Detect native Windows shells and stop with WSL2 guidance.
3. Ensure bootstrap prerequisites such as `git`, `curl`, and `python3` are present or guide/install them with confirmation.
4. Install OpenCode when missing.
5. Install Gentle AI when missing.
6. Run deterministic Gentle AI setup for the full ecosystem:
   `gentle-ai install --agents opencode,codex --preset full-gentleman --components context7,persona,engram,gga,permissions,sdd,skills`,
   then `gentle-ai sync`.
7. Ensure `~/.config/opencode/opencode.json` exists.
8. Delegate Codex compatibility installation to `./install.sh`.
9. Run `codex-sdd-sync` and validation when possible.
10. Print Codex Desktop/CLI next steps.

## Non-goals

- Installing Codex Desktop as a GUI application.
- Managing OpenAI/API credentials.
- Guaranteeing native Windows support in the first version.
- Replacing `install.sh` as the compatibility-layer installer.
- Silently overwriting user configuration.

## Platform Policy

| Platform | Support level | Notes |
| --- | --- | --- |
| macOS | Supported | Primary path for Codex Desktop users. |
| Linux | Supported | CLI and desktop environments. |
| WSL2 | Supported | Recommended Windows path. |
| Native Windows | Unsupported/experimental | Stop early and recommend WSL2. |

## Safety Requirements

- The script must be idempotent.
- Remote installers must require confirmation unless `--yes` is passed.
- `--dry-run` must avoid network installers and home-directory mutations.
- Existing `install.sh` behavior must remain compatibility-layer focused.
- Missing interactive configuration must produce rerunnable instructions.

## CLI Requirements

The full installer should support:

```txt
--dry-run
--yes / -y
--prefix DIR
--no-sync
--skip-gentle
--skip-opencode
--install-codex-cli
--gentle-agents LIST
--gentle-preset NAME
--gentle-components LIST
```

## Acceptance Criteria

- `./install-full.sh --dry-run` shows the bootstrap flow without mutating the machine.
- `./install-full.sh` detects macOS/Linux/WSL2 and rejects native Windows shells with WSL2 guidance.
- The installer can install missing OpenCode and Gentle AI with confirmation.
- The installer runs Gentle AI setup/sync for `opencode,codex` with the full component ecosystem before invoking the Codex SDD compatibility installer.
- The installer delegates to `./install.sh` rather than duplicating compatibility-layer logic.
- README documents the full bootstrap path separately from the existing sync-only path.
- Validation still uses `codex-sdd-sync` and `python3.11 ~/.codex/scripts/sync-opencode-sdd.py --test` when available.
