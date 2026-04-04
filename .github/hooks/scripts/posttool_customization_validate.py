import json
import os
import re
import subprocess
import sys
from pathlib import Path


RELEVANT_PREFIXES = (
    ".github/",
    "tracking/",
)

HOOK_EVENTS = {
    "SessionStart",
    "PreToolUse",
    "PostToolUse",
}

HOOK_FILENAME_PATTERN = re.compile(r"^\d{2}-[a-z0-9-]+\.json$")
HOOK_PREFIX_PATTERN = re.compile(r"^(\d{2})-")
SCRIPT_PATH_PATTERN = re.compile(r"\.github/hooks/scripts/[A-Za-z0-9_.-]+\.py")


def load_payload():
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {"raw": raw}


def find_cwd(payload):
    if isinstance(payload, dict):
        for key in ("cwd", "workspaceFolder", "workspacePath", "path"):
            value = payload.get(key)
            if isinstance(value, str) and value:
                return value
        for value in payload.values():
            found = find_cwd(value)
            if found:
                return found
    elif isinstance(payload, list):
        for item in payload:
            found = find_cwd(item)
            if found:
                return found
    return os.getcwd()


def git(args, cwd):
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        check=False,
    )
    return result.stdout.strip()


def changed_files(repo_root: str):
    output = git(["status", "--porcelain"], repo_root)
    files = []
    for line in output.splitlines():
        if len(line) < 4:
            continue
        path = line[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", 1)[1].strip()
        normalized = path.replace("\\", "/")
        if normalized.startswith(RELEVANT_PREFIXES):
            files.append(normalized)
    return files


def hook_config_files(repo_root: str):
    hooks_dir = Path(repo_root, ".github", "hooks")
    if not hooks_dir.exists():
        return []
    return sorted(
        path for path in hooks_dir.glob("*.json") if path.is_file()
    )


def validate_markdown_frontmatter(path: Path):
    text = path.read_text(encoding="utf-8")
    errors = []
    if path.name == "AGENTS.md":
        return errors
    if path.suffix == ".md" and (path.name.endswith(".agent.md") or path.name.endswith(".instructions.md") or path.name == "SKILL.md"):
        lines = text.splitlines()
        if not lines or lines[0].strip() != "---":
            errors.append(f"{path.as_posix()}: missing YAML frontmatter start")
            return errors
        try:
            end_index = lines[1:].index("---") + 1
        except ValueError:
            errors.append(f"{path.as_posix()}: missing YAML frontmatter end")
            return errors
        frontmatter = "\n".join(lines[1:end_index])
        if "description:" not in frontmatter:
            errors.append(f"{path.as_posix()}: frontmatter missing description")
    return errors


def validate_hook_json(path: Path):
    relative_path = path.as_posix()
    errors = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"{relative_path}: invalid JSON ({exc})"], []

    if not HOOK_FILENAME_PATTERN.match(path.name):
        errors.append(
            f"{relative_path}: filename must match NN-kebab-case.json"
        )

    hooks = data.get("hooks")
    if not isinstance(hooks, dict) or not hooks:
        errors.append(f"{relative_path}: missing top-level hooks key")
        return errors, []

    registrations = []
    for event_name, entries in hooks.items():
        if event_name not in HOOK_EVENTS:
            errors.append(f"{relative_path}: unsupported hook event {event_name}")
            continue
        if not isinstance(entries, list) or not entries:
            errors.append(f"{relative_path}: hook event {event_name} must contain a non-empty list")
            continue
        for index, entry in enumerate(entries, start=1):
            if not isinstance(entry, dict):
                errors.append(f"{relative_path}: hook entry {event_name}[{index}] must be an object")
                continue
            if entry.get("type") != "command":
                errors.append(f"{relative_path}: hook entry {event_name}[{index}] must have type=command")
            command_paths = referenced_script_paths(entry)
            if not command_paths:
                errors.append(f"{relative_path}: hook entry {event_name}[{index}] must reference a script under .github/hooks/scripts/")
                continue
            for script_path in command_paths:
                script_file = path.parent.parent / script_path.relative_to(".github/hooks")
                if not script_file.exists():
                    errors.append(f"{relative_path}: referenced script does not exist: {script_path.as_posix()}")
                registrations.append((event_name, script_path.as_posix(), relative_path))
    return errors, registrations


def referenced_script_paths(entry):
    matches = []
    for key in ("command", "windows"):
        value = entry.get(key)
        if not isinstance(value, str):
            continue
        for match in SCRIPT_PATH_PATTERN.findall(value):
            matches.append(Path(match.replace("\\", "/")))
    unique = []
    seen = set()
    for item in matches:
        normalized = item.as_posix()
        if normalized in seen:
            continue
        seen.add(normalized)
        unique.append(item)
    return unique


def validate_hook_suite(repo_root: str):
    errors = []
    coverage = {}
    hook_files = hook_config_files(repo_root)
    seen_prefixes = {}
    previous_prefix = None

    for hook_file in hook_files:
        file_errors, registrations = validate_hook_json(hook_file)
        errors.extend(file_errors)

        prefix_match = HOOK_PREFIX_PATTERN.match(hook_file.name)
        if prefix_match:
            prefix = int(prefix_match.group(1))
            existing = seen_prefixes.get(prefix)
            if existing is not None:
                errors.append(
                    "duplicate hook prefix "
                    f"{prefix_match.group(1)}: {existing.as_posix()}, {hook_file.as_posix()}"
                )
            elif previous_prefix is not None and prefix <= previous_prefix:
                errors.append(
                    "hook prefixes must be strictly increasing: "
                    f"{hook_file.as_posix()} follows prefix {previous_prefix:02d}"
                )
            seen_prefixes[prefix] = hook_file
            previous_prefix = prefix

        for event_name, script_path, source_file in registrations:
            key = (event_name, script_path)
            coverage.setdefault(key, []).append(source_file)
    for (event_name, script_path), sources in sorted(coverage.items()):
        if len(sources) > 1:
            joined_sources = ", ".join(sorted(sources))
            errors.append(
                "duplicate hook coverage for "
                f"{event_name} -> {script_path}: {joined_sources}"
            )
    return errors


payload = load_payload()
cwd = find_cwd(payload)
repo_root = git(["rev-parse", "--show-toplevel"], cwd) or cwd
files = changed_files(repo_root)
issues = []
hooks_changed = any(relative.startswith(".github/hooks/") for relative in files)

for relative in files:
    path = Path(repo_root, relative)
    if not path.exists() or path.is_dir():
        continue
    if path.suffix == ".md":
        issues.extend(validate_markdown_frontmatter(path))

if hooks_changed:
    issues.extend(validate_hook_suite(repo_root))

if issues:
    json.dump(
        {
            "decision": "block",
            "systemMessage": "Hook validation failed:\n- " + "\n- ".join(issues),
            "stopReason": "Customization validation failed.",
        },
        sys.stdout,
    )
else:
    json.dump({"continue": True}, sys.stdout)