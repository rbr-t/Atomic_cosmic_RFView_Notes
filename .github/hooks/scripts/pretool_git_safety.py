import json
import os
import subprocess
import sys
from typing import Any


DENY_PATTERNS = [
    "git reset --hard",
    "git checkout --",
    "git clean -fd",
    "git clean -xdf",
]

ASK_PATTERNS = [
    "git push",
    "git push origin --delete",
    "git push --delete",
    "git branch -d ",
    "git branch -D ",
]


def load_payload() -> Any:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {"raw": raw}


def flatten(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True).lower()
    except Exception:
        return str(value).lower()


def find_cwd(payload: Any) -> str:
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


def git_branch(cwd: str) -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            check=True,
        )
        return result.stdout.strip()
    except Exception:
        return ""


payload = load_payload()
payload_text = flatten(payload)
cwd = find_cwd(payload)
branch = git_branch(cwd)

for pattern in DENY_PATTERNS:
    if pattern.lower() in payload_text:
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Blocked destructive git command: {pattern}",
                },
                "systemMessage": "Hook blocked a destructive git command. Use a safer, explicit alternative.",
            },
            sys.stdout,
        )
        sys.exit(0)

for pattern in ASK_PATTERNS:
    if pattern.lower() in payload_text:
        reason = f"Hook requests confirmation for higher-risk git operation matching: {pattern}"
        if "git push" in pattern and branch == "main":
            reason = "Hook requests confirmation before pushing from main."
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": reason,
                },
                "systemMessage": reason,
            },
            sys.stdout,
        )
        sys.exit(0)

json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "No git safety rule triggered.",
        }
    },
    sys.stdout,
)