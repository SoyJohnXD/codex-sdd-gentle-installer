#!/usr/bin/env python3
"""Sync gentle-ai/OpenCode SDD workflow configuration into Codex.

This script is intentionally stdlib-only. Run it after updating gentle-ai/OpenCode
when you want Codex custom agents, SDD prompts, and workflow instructions to mirror
OpenCode's SDD setup.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Dict, Any, Iterable

HOME = Path.home()
OPENCODE_DIR = HOME / ".config" / "opencode"
CODEX_DIR = HOME / ".codex"
AGENTS_DIR = CODEX_DIR / "agents"
PROMPTS_DIR = CODEX_DIR / "prompts"
CODEX_SCRIPTS_DIR = CODEX_DIR / "scripts"
USER_SKILLS_DIR = HOME / ".agents" / "skills"
STATE_PATH = CODEX_DIR / "sdd-sync-state.json"
SDD_PROFILE_PATH = CODEX_DIR / "sdd-profile-instructions.md"

START = "<!-- gentle-ai:codex-sdd-workflow -->"
END = "<!-- /gentle-ai:codex-sdd-workflow -->"
SYNC_START = "<!-- gentle-ai:codex-sync-protocol -->"
SYNC_END = "<!-- /gentle-ai:codex-sync-protocol -->"

PHASES = [
    "sdd-init",
    "sdd-explore",
    "sdd-propose",
    "sdd-spec",
    "sdd-design",
    "sdd-tasks",
    "sdd-apply",
    "sdd-verify",
    "sdd-archive",
    "sdd-onboard",
]
ALL_AGENTS = ["sdd-orchestrator"] + PHASES

SANDBOX_BY_AGENT = {
    "sdd-explore": "read-only",
}
DEFAULT_SANDBOX = "workspace-write"

DEFAULT_REASONING = {
    "sdd-init": "high",
    "sdd-explore": "high",
    "sdd-propose": "high",
    "sdd-spec": "high",
    "sdd-design": "high",
    "sdd-tasks": "medium",
    "sdd-apply": "medium",
    "sdd-verify": "medium",
    "sdd-archive": "medium",
    "sdd-onboard": "high",
    "sdd-orchestrator": "high",
}


def read_text(path: Path, default: str = "") -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        return default


def write_text_if_changed(path: Path, content: str, dry_run: bool, changed: list[str]) -> None:
    old = read_text(path, None)  # type: ignore[arg-type]
    if old == content:
        return
    changed.append(str(path))
    if not dry_run:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def json_string(value: str) -> str:
    # JSON string syntax is valid TOML basic string syntax for our content.
    return json.dumps(value, ensure_ascii=False)


def normalize_model(model: str | None) -> str:
    if not model:
        return "gpt-5.4"
    return model[len("openai/"):] if model.startswith("openai/") else model


def extract_file_prompt(prompt_ref: str | None) -> str:
    if not prompt_ref:
        return ""
    m = re.fullmatch(r"\{file:(.+)\}", prompt_ref.strip())
    if m:
        return read_text(Path(m.group(1)))
    return prompt_ref


def load_opencode() -> Dict[str, Any]:
    path = OPENCODE_DIR / "opencode.json"
    if not path.exists():
        raise SystemExit(f"Missing OpenCode config: {path}")
    return json.loads(path.read_text())


def phase_developer_instructions(name: str, prompt_body: str) -> str:
    skill_path = CODEX_DIR / "skills" / name / "SKILL.md"
    return f"""You are the Codex `{name}` SDD phase agent, synchronized from gentle-ai/OpenCode.

You are not alone in the codebase: other agents may be editing or researching in parallel. Do not revert or overwrite their work. Keep your scope narrow and follow the assigned phase exactly.

Before doing phase work:
1. Read `{skill_path}` when available and follow it as the source of truth.
2. Use Engram as the default artifact store.
3. If mem_search returns a preview, call mem_get_observation before relying on artifact content.
4. If you make important discoveries, decisions, configuration changes, or bug fixes, save them to Engram with mem_save.

Artifact topic keys:
- Project context: `sdd-init/{{project}}`
- Exploration: `sdd/{{change-name}}/explore`
- Proposal: `sdd/{{change-name}}/proposal`
- Spec: `sdd/{{change-name}}/spec`
- Design: `sdd/{{change-name}}/design`
- Tasks: `sdd/{{change-name}}/tasks`
- Apply progress: `sdd/{{change-name}}/apply-progress`
- Verify report: `sdd/{{change-name}}/verify-report`
- Archive report: `sdd/{{change-name}}/archive-report`

Return: status, executive_summary, artifacts, risks, next_recommended, files_changed, key_learnings.

## Synced OpenCode prompt

{prompt_body}
"""


def orchestrator_instructions(opencode_prompt: str) -> str:
    return f"""You are the Codex SDD orchestrator, synchronized from gentle-ai/OpenCode. Coordinate; do not inflate your own context by doing SDD phase work inline.

You are not alone in the codebase. Other agents may be running in parallel. Do not revert their edits; integrate or route around them.

## Codex compatibility layer

Treat these user intents as workflow triggers, even if custom slash prompts are not available in the current Codex surface:
- `sdd init` / `sdd-init` -> run `sdd-init`.
- `sdd explore <topic>` / `sdd-explore <topic>` -> ensure init, then run `sdd-explore`.
- `sdd new <change>` / `sdd-new <change>` -> ensure init, run `sdd-explore`, then `sdd-propose`.
- `sdd ff <change>` / `sdd-ff <change>` -> ensure init, run `sdd-propose`, then `sdd-spec` and `sdd-design`, then `sdd-tasks`.
- `sdd continue <change>` / `sdd-continue <change>` -> inspect Engram artifacts and launch the next dependency-ready phase.
- `sdd apply <change>` / `sdd-apply <change>` -> ensure init, then run `sdd-apply`.
- `sdd verify <change>` / `sdd-verify <change>` -> ensure init, then run `sdd-verify`.
- `sdd archive <change>` / `sdd-archive <change>` -> ensure init, then run `sdd-archive`.
- `sdd onboard` / `sdd-onboard` -> run `sdd-onboard`.

## AUTO / READY-TO-EXEC mode

When the user says any of these:
- `sdd auto <change>`
- `sdd-auto <change>`
- `sdd exec <change>`
- `sdd-exec <change>`
- `ready to exec <change>`
- Hermes launches a task that is already planned, ready, or asks to execute/complete an SDD change

Run the workflow to completion unless blocked by missing information, failing verification, or required approval:
1. Ensure `sdd-init/{{project}}` exists; if missing, run `sdd-init`.
2. Inspect Engram artifacts for `sdd/<change>/...`.
3. If proposal/spec/design/tasks are missing, create the missing planning artifacts in dependency order.
4. Run `sdd-apply` until all tasks are complete or blocked.
5. Run `sdd-verify`.
6. If verification passes with no CRITICAL findings, run `sdd-archive`.
7. If verification fails, run one fix loop: `sdd-apply` for verification findings, then `sdd-verify` again. Stop after that if still failing and report blockers.

Auto mode is meant for Hermes/background delegation. Be concise, avoid asking between phases, and complete the change. Still ask before destructive git operations or unsafe external side effects.

## Init guard
Before any SDD phase except sdd-init itself, search Engram for topic `sdd-init/{{project}}`. If not found, run sdd-init first silently, then continue.

## Artifact store
Default to Engram. mem_search returns previews only; call mem_get_observation when content matters.

## Delegation policy
Use subagents for phase work. Keep local work to orchestration, artifact lookup, and synthesis. Parallelize only safe independent phases; do not run apply and verify in parallel for the same change.

## Synced OpenCode orchestrator prompt

{opencode_prompt}
"""


def render_agent(name: str, cfg: Dict[str, Any], prompt_body: str) -> str:
    model = normalize_model(cfg.get("model"))
    effort = cfg.get("reasoningEffort") or DEFAULT_REASONING.get(name, "medium")
    sandbox = SANDBOX_BY_AGENT.get(name, DEFAULT_SANDBOX)
    desc = cfg.get("description") or f"Codex SDD agent {name}"
    if name == "sdd-orchestrator":
        dev = orchestrator_instructions(prompt_body)
        nicknames = 'nickname_candidates = ["Maestro", "Planner", "Coordinator"]\n'
    else:
        dev = phase_developer_instructions(name, prompt_body)
        nicknames = ""
    return (
        f'name = {json_string(name)}\n'
        f'description = {json_string(desc)}\n'
        f'model = {json_string(model)}\n'
        f'model_reasoning_effort = {json_string(effort)}\n'
        f'sandbox_mode = {json_string(sandbox)}\n'
        f'{nicknames}'
        f'developer_instructions = {json_string(dev)}\n'
    )


def replace_block(content: str, start: str, end: str, block: str) -> str:
    full = f"{start}\n{block.rstrip()}\n{end}"
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if pattern.search(content):
        return pattern.sub(full, content)
    return content.rstrip() + "\n\n" + full + "\n"


def workflow_block() -> str:
    return """## Codex SDD Workflow

When the user asks for `sdd`, `sdd-*`, Spec-Driven Development, planning phases, or workflow orchestration, use the configured Codex SDD workflow.

Configured files:
- Sync script: `~/.codex/scripts/sync-opencode-sdd.py`
- Orchestrator custom agent: `~/.codex/agents/sdd-orchestrator.toml`
- Phase custom agents: `~/.codex/agents/sdd-*.toml`
- SDD skills: `~/.codex/skills/sdd-*` and symlinks under `~/.agents/skills`
- Prompt templates: `~/.codex/prompts/sdd-*.md`

Default artifact store is Engram. Before every SDD command, ensure `sdd-init/{project}` exists in Engram; if missing, run SDD init first.

Command mapping:
- `sdd init` / `sdd-init` -> `sdd-init`
- `sdd explore <topic>` / `sdd-explore <topic>` -> `sdd-explore`
- `sdd new <change>` / `sdd-new <change>` -> `sdd-explore` then `sdd-propose`
- `sdd ff <change>` / `sdd-ff <change>` -> `sdd-propose`, `sdd-spec`, `sdd-design`, `sdd-tasks`
- `sdd continue <change>` / `sdd-continue <change>` -> next missing phase by dependency graph
- `sdd apply <change>` / `sdd-apply <change>` -> `sdd-apply`
- `sdd verify <change>` / `sdd-verify <change>` -> `sdd-verify`
- `sdd archive <change>` / `sdd-archive <change>` -> `sdd-archive`
- `sdd onboard` / `sdd-onboard` -> `sdd-onboard`
- `sdd auto <change>` / `sdd-auto <change>` / `sdd exec <change>` / `ready to exec <change>` -> run missing planning, apply, verify, and archive if verification passes.

## AUTO / READY-TO-EXEC mode

Auto mode is for Hermes/background ready-to-exec tasks: do not pause between phases unless blocked, verification fails after one fix loop, or approval is required for destructive side effects. It should complete missing planning, apply, verify, and archive when verification passes."""


def sdd_profile_text() -> str:
    return """# Codex SDD Orchestrator Profile

You are running in the dedicated SDD profile. Behave as the `sdd-orchestrator` coordinator.

## Primary role

Coordinate Spec-Driven Development workflows. Keep the main context thin, delegate phase work to SDD subagents, synthesize results, and persist artifacts in Engram.

## Required behavior

- Treat `sdd init`, `sdd-new`, `sdd ff`, `sdd apply`, `sdd verify`, `sdd archive`, `sdd auto`, `sdd-exec`, and `ready to exec` as SDD workflow triggers.
- Before any SDD command except init, ensure `sdd-init/{project}` exists in Engram; if missing, run SDD init first.
- Use SDD phase subagents for real phase work: `sdd-init`, `sdd-explore`, `sdd-propose`, `sdd-spec`, `sdd-design`, `sdd-tasks`, `sdd-apply`, `sdd-verify`, `sdd-archive`.
- In `sdd auto` / ready-to-exec mode, complete missing planning, apply, verify, and archive if verification passes. Do one fix loop after verification failure, then stop and report blockers.
- Do not ask between phases in auto mode unless blocked, verification fails after one fix loop, or approval is required for destructive side effects.
- Preserve the Engram memory protocol from the global instructions. Save significant decisions, discoveries, config changes, and bug fixes.

## Artifact topic keys

- Project context: `sdd-init/{project}`
- Exploration: `sdd/{change-name}/explore`
- Proposal: `sdd/{change-name}/proposal`
- Spec: `sdd/{change-name}/spec`
- Design: `sdd/{change-name}/design`
- Tasks: `sdd/{change-name}/tasks`
- Apply progress: `sdd/{change-name}/apply-progress`
- Verify report: `sdd/{change-name}/verify-report`
- Archive report: `sdd/{change-name}/archive-report`
"""


def ensure_sdd_profile(dry_run: bool, changed: list[str]) -> None:
    write_text_if_changed(SDD_PROFILE_PATH, sdd_profile_text(), dry_run, changed)
    path = CODEX_DIR / "config.toml"
    content = read_text(path)
    block = """
[profiles.sdd]
model = "gpt-5.5"
model_reasoning_effort = "high"
model_instructions_file = "{profile}"
""".format(profile=str(SDD_PROFILE_PATH))
    if "[profiles.sdd]" not in content:
        content = content.rstrip() + "\n" + block + "\n"
        write_text_if_changed(path, content, dry_run, changed)


def sync_protocol_block() -> str:
    return """## OpenCode -> Codex Sync Protocol

When the user says they updated OpenCode/gentle-ai and asks to "sincronízate", "sync Codex", "actualiza la configuración", or similar:
1. Run `python3 ~/.codex/scripts/sync-opencode-sdd.py --check` to see drift.
2. If drift exists or the user asked to update, run `python3 ~/.codex/scripts/sync-opencode-sdd.py`.
3. Run `python3 ~/.codex/scripts/sync-opencode-sdd.py --test`.
4. Summarize changed files and tell the user to restart Codex CLI/Desktop if needed.

Do not hand-edit generated `~/.codex/agents/sdd-*.toml` unless the sync script is also updated. OpenCode remains the upstream source for SDD models/prompts; Codex receives a generated compatibility layer."""


def update_instruction_files(dry_run: bool, changed: list[str]) -> None:
    for path in [CODEX_DIR / "engram-instructions.md", CODEX_DIR / "agents.md"]:
        content = read_text(path)
        content = replace_block(content, START, END, workflow_block())
        content = replace_block(content, SYNC_START, SYNC_END, sync_protocol_block())
        write_text_if_changed(path, content, dry_run, changed)


def ensure_config_agents(dry_run: bool, changed: list[str]) -> None:
    path = CODEX_DIR / "config.toml"
    content = read_text(path)
    if "[agents]" not in content:
        content = content.rstrip() + "\n\n[agents]\nmax_threads = 6\nmax_depth = 1\njob_max_runtime_seconds = 1800\n"
    else:
        # Keep it simple and idempotent: ensure keys exist after [agents].
        if "max_threads" not in content:
            content = content.rstrip() + "\nmax_threads = 6\n"
        if "max_depth" not in content:
            content = content.rstrip() + "\nmax_depth = 1\n"
        if "job_max_runtime_seconds" not in content:
            content = content.rstrip() + "\njob_max_runtime_seconds = 1800\n"
    write_text_if_changed(path, content.rstrip() + "\n", dry_run, changed)


def sync_skills(dry_run: bool, changed: list[str]) -> None:
    src_root = CODEX_DIR / "skills"
    if not src_root.exists():
        return
    if not dry_run:
        USER_SKILLS_DIR.mkdir(parents=True, exist_ok=True)
    for src in src_root.iterdir():
        if src.name.startswith("."):
            continue
        dst = USER_SKILLS_DIR / src.name
        if dst.exists() or dst.is_symlink():
            continue
        changed.append(str(dst))
        if not dry_run:
            try:
                dst.symlink_to(src, target_is_directory=src.is_dir())
            except OSError:
                if src.is_dir():
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)


def sync_prompts(dry_run: bool, changed: list[str]) -> None:
    commands_dir = OPENCODE_DIR / "commands"
    for src in sorted(commands_dir.glob("sdd-*.md")):
        content = src.read_text()
        note = "\n\n---\nCodex compatibility: if this prompt is not surfaced as a slash command, type the same command textually (for example `sdd auto <change>`).\n"
        write_text_if_changed(PROMPTS_DIR / src.name, content.rstrip() + note, dry_run, changed)
    auto_prompts = {
        "sdd-auto.md": "Run SDD AUTO mode for change: $ARGUMENTS\nComplete missing planning, apply, verify, and archive if verification passes. Use sdd-orchestrator. Artifact store: engram. Do not pause between phases unless blocked or approval is required.",
        "sdd-exec.md": "Execute ready-to-exec SDD change: $ARGUMENTS\nUse AUTO mode. If tasks already exist, apply -> verify -> archive if verification passes. If artifacts are missing, create missing planning artifacts first.",
        "sdd-sync.md": "Synchronize Codex SDD workflow from OpenCode/gentle-ai by running `python3 ~/.codex/scripts/sync-opencode-sdd.py`, then `python3 ~/.codex/scripts/sync-opencode-sdd.py --test`. Summarize changes.",
    }
    for name, body in auto_prompts.items():
        text = f"---\ndescription: {name[:-3]} workflow prompt\n---\n\n{body}\n"
        write_text_if_changed(PROMPTS_DIR / name, text, dry_run, changed)


def sync_agents(data: Dict[str, Any], dry_run: bool, changed: list[str]) -> None:
    agents = data.get("agent", {})
    for name in ALL_AGENTS:
        cfg = agents.get(name, {})
        prompt_body = extract_file_prompt(cfg.get("prompt"))
        if not prompt_body and name != "sdd-orchestrator":
            prompt_body = read_text(OPENCODE_DIR / "prompts" / "sdd" / f"{name}.md")
        rendered = render_agent(name, cfg, prompt_body)
        write_text_if_changed(AGENTS_DIR / f"{name}.toml", rendered, dry_run, changed)


def write_state(dry_run: bool, changed: list[str]) -> None:
    files: Dict[str, str] = {}
    for root in [OPENCODE_DIR / "opencode.json", OPENCODE_DIR / "commands", OPENCODE_DIR / "prompts" / "sdd"]:
        if root.is_file():
            files[str(root)] = sha256(root)
        elif root.is_dir():
            for p in sorted(root.glob("**/*")):
                if p.is_file() and "node_modules" not in p.parts:
                    files[str(p)] = sha256(p)
    state = {
        "source": str(OPENCODE_DIR),
        "target": str(CODEX_DIR),
        "files": files,
        "agents": ALL_AGENTS,
    }
    write_text_if_changed(STATE_PATH, json.dumps(state, indent=2, sort_keys=True) + "\n", dry_run, changed)


def run_test() -> None:
    missing = [str(AGENTS_DIR / f"{name}.toml") for name in ALL_AGENTS if not (AGENTS_DIR / f"{name}.toml").exists()]
    if missing:
        raise SystemExit("Missing generated agents:\n" + "\n".join(missing))
    try:
        import tomllib  # Python 3.11+
    except Exception as exc:
        raise SystemExit(f"Python tomllib unavailable; use python3.11 for tests: {exc}")
    for p in sorted(AGENTS_DIR.glob("sdd*.toml")):
        tomllib.loads(p.read_text())
    tomllib.loads((CODEX_DIR / "config.toml").read_text())
    if not SDD_PROFILE_PATH.exists():
        raise SystemExit(f"Missing SDD profile instructions: {SDD_PROFILE_PATH}")
    active_profile = read_text(SDD_PROFILE_PATH)
    if "sdd-orchestrator" not in active_profile or "ready-to-exec" not in active_profile:
        raise SystemExit("SDD profile instructions missing orchestrator/auto content")
    for name in ["sdd-auto.md", "sdd-exec.md", "sdd-sync.md"]:
        if not (PROMPTS_DIR / name).exists():
            raise SystemExit(f"Missing prompt: {PROMPTS_DIR / name}")
    active = read_text(CODEX_DIR / "engram-instructions.md")
    required = ["AUTO / READY-TO-EXEC", "OpenCode -> Codex Sync Protocol", "sdd auto <change>"]
    for needle in required:
        if needle not in active:
            raise SystemExit(f"Active instructions missing: {needle}")
    print("OK: Codex SDD sync test passed")


def run_sync(dry_run: bool = False) -> list[str]:
    data = load_opencode()
    changed: list[str] = []
    if not dry_run:
        AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        PROMPTS_DIR.mkdir(parents=True, exist_ok=True)
        CODEX_SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    sync_agents(data, dry_run, changed)
    sync_prompts(dry_run, changed)
    sync_skills(dry_run, changed)
    ensure_config_agents(dry_run, changed)
    ensure_sdd_profile(dry_run, changed)
    update_instruction_files(dry_run, changed)
    write_state(dry_run, changed)
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Show what would change and exit non-zero if drift exists")
    parser.add_argument("--dry-run", action="store_true", help="Show what would change without writing")
    parser.add_argument("--test", action="store_true", help="Validate generated Codex SDD configuration")
    args = parser.parse_args()

    if args.test:
        run_test()
        return

    dry = args.dry_run or args.check
    changed = run_sync(dry_run=dry)
    if changed:
        label = "Would update" if dry else "Updated"
        print(f"{label} {len(changed)} path(s):")
        for p in changed:
            print(f"- {p}")
    else:
        print("Codex SDD workflow already in sync")
    if args.check and changed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
