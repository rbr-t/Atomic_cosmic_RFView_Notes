import json
import os
import subprocess
import sys
from pathlib import Path


RELEVANT_PREFIXES = (
    ".github/",
    "tracking/",
)


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
    errors = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"{path.as_posix()}: invalid JSON ({exc})"]
    if "hooks" not in data:
        errors.append(f"{path.as_posix()}: missing top-level hooks key")
    return errors


payload = load_payload()
cwd = find_cwd(payload)
repo_root = git(["rev-parse", "--show-toplevel"], cwd) or cwd
files = changed_files(repo_root)
issues = []

for relative in files:
    path = Path(repo_root, relative)
    if not path.exists() or path.is_dir():
        continue
    if relative.startswith(".github/hooks/") and path.suffix == ".json":
        issues.extend(validate_hook_json(path))
    elif path.suffix == ".md":
        issues.extend(validate_markdown_frontmatter(path))

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