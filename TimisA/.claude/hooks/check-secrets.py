#!/usr/bin/env python3
"""
PreToolUse hook — blocks writes of plaintext secrets to sensitive files.

Triggered by Claude Code before any Write or Edit tool call.
Input: JSON on stdin with tool name and input parameters.
Exit 0: allow the tool call.
Exit 1 + message on stderr: block the tool call and show the message.
"""
import json
import re
import sys

WATCHED_EXTENSIONS = {".tf", ".env", ".ini", ".py", ".yml", ".yaml"}

SECRET_PATTERNS = [
    (r'password\s*=\s*["\'][^${\s][^"\']{4,}["\']', "plaintext password assignment"),
    (r'secret\s*=\s*["\'][^${\s][^"\']{4,}["\']',   "plaintext secret assignment"),
    (r'(?i)aws_secret_access_key\s*=\s*["\'][A-Za-z0-9/+=]{20,}["\']', "AWS secret key"),
    (r'(?i)aws_access_key_id\s*=\s*["\']AKIA[A-Z0-9]{16}["\']',        "AWS access key ID"),
    (r'psycopg2\.connect\s*\([^)]*password\s*=\s*[^\s,)]+',             "hardcoded DB connection string"),
]

SAFE_PATTERNS = [
    r'os\.environ',
    r'os\.getenv',
    r'var\.',
    r'data\.',
    r'aws_secretsmanager',
    r'local_dev_only',
    r'placeholder',
    r'change.in.prod',
    r'CHANGE_ME',
]


def is_safe(line: str) -> bool:
    return any(re.search(p, line, re.IGNORECASE) for p in SAFE_PATTERNS)


def check_content(content: str, file_path: str) -> list[str]:
    violations = []
    ext = "." + file_path.rsplit(".", 1)[-1] if "." in file_path else ""

    if ext not in WATCHED_EXTENSIONS:
        return violations

    for i, line in enumerate(content.splitlines(), 1):
        if is_safe(line):
            continue
        for pattern, label in SECRET_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                violations.append(f"  Line {i}: {label} — use AWS Secrets Manager or env var (ADR-0003)")
                break

    return violations


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)  # not a JSON payload — allow

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {})

    if tool_name not in ("Write", "Edit"):
        sys.exit(0)

    file_path = tool_input.get("file_path", "")
    content = tool_input.get("content") or tool_input.get("new_string", "")

    violations = check_content(content, file_path)

    if violations:
        print(
            f"\n🚫 BLOCKED by check-secrets hook\n"
            f"File: {file_path}\n"
            f"Potential plaintext secrets detected:\n" + "\n".join(violations) + "\n\n"
            f"Fix: reference secrets via AWS Secrets Manager ARN or os.environ[] — never hardcode values.\n"
            f"See ADR-0003 and TimisA/CLAUDE.md for the approved pattern.\n",
            file=sys.stderr,
        )
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
