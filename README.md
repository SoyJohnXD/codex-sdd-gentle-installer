# Codex SDD Gentle Installer

Installs the Codex compatibility layer for the gentle-ai/OpenCode SDD workflow.

## Install order

1. Install Codex CLI/Desktop.
2. Install gentle-ai/OpenCode and let it create `~/.config/opencode/opencode.json`.
3. Run this installer:

```bash
./install.sh
```

Restart Codex after installation.

## What it installs

- `~/.codex/scripts/sync-opencode-sdd.py`
- `~/.local/bin/codex-sdd-sync`
- `~/.local/bin/codex-sdd` — opens Codex with the dedicated SDD profile
- generated Codex SDD agents under `~/.codex/agents/sdd-*.toml`
- generated prompts under `~/.codex/prompts/sdd-*.md`
- workflow/sync instructions in `~/.codex/engram-instructions.md` and `~/.codex/agents.md`
- skill discovery symlinks under `~/.agents/skills`

## After updating gentle-ai/OpenCode

Run:

```bash
codex-sdd-sync --check
codex-sdd-sync
python3.11 ~/.codex/scripts/sync-opencode-sdd.py --test
```

Or tell Codex: “actualicé OpenCode/gentle-ai, sincronízate”.

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
