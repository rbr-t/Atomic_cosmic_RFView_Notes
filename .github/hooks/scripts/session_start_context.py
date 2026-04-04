import json
import os
import subprocess
import sys
from typing import Any


def load_payload() -> Any:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {"raw": raw}


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


def git(args, cwd):
    try:
        result = subprocess.run(
            ["git"] + args,
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
cwd = find_cwd(payload)
repo_root = git(["rev-parse", "--show-toplevel"], cwd) or cwd
repo_name = os.path.basename(repo_root.rstrip("/\\"))
branch = git(["rev-parse", "--abbrev-ref", "HEAD"], repo_root) or "unknown"
dirty = bool(git(["status", "--short"], repo_root))

if repo_name == "Global_Agentic_Operating_System":
    role = "global source-of-truth"
    note = "Changes here may require downstream propagation."
else:
    role = "downstream consumer repo"
    note = "Keep repo-local overlays distinct from the shared baseline."

message = (
    f"Hook context: repo={repo_name}, branch={branch}, "
    f"state={'dirty' if dirty else 'clean'}, role={role}. {note}"
)

json.dump({"continue": True, "systemMessage": message}, sys.stdout)