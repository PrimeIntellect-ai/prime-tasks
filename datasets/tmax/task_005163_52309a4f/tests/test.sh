#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import os
import secrets
import stat
import subprocess
from pathlib import Path


def run_filter(script_path, content):
    return subprocess.run(
        ["bash", script_path],
        input=content,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_ssh_audit_fixed():
    """Verify that the ssh-audit.py script has been fixed and runs successfully."""
    script_path = "/app/ssh-audit-3.1.0/ssh-audit.py"
    assert os.path.isfile(script_path), f"ssh-audit script not found at {script_path}"

    result = subprocess.run(
        ["python3", script_path, "-h"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"ssh-audit.py failed to run. Exit code: {result.returncode}, Stderr: {result.stderr}"

    # Ensure the broken import was actually repaired and the vendored program was
    # not replaced by an empty/no-op script.
    source = Path(script_path).read_text()
    tree = ast.parse(source, filename=script_path)
    imports_sys = any(
        (isinstance(node, ast.Import) and any(alias.name == "sys" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "sys")
        for node in ast.walk(tree)
    )
    assert imports_sys, "ssh-audit.py still does not import sys"
    assert any(isinstance(node, ast.FunctionDef) and node.name == "main" for node in ast.walk(tree)), "ssh-audit main function is missing"

    harness = r'''
import runpy
import sys

path = sys.argv[1]
calls = []
original_exit = sys.exit
class ExpectedExit(BaseException):
    pass

def checked_exit(code=0):
    calls.append(code)
    raise ExpectedExit()

sys.exit = checked_exit
try:
    try:
        runpy.run_path(path, run_name="__main__")
    except ExpectedExit:
        pass
finally:
    sys.exit = original_exit

if calls != [0]:
    raise SystemExit("vendored main did not execute its successful exit path: %r" % (calls,))
'''
    exercised = subprocess.run(
        ["python3", "-c", harness, script_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert exercised.returncode == 0, exercised.stderr or exercised.stdout


def test_validate_auth_keys_filter():
    """Verify the filter against the provided clean and evil corpora."""
    script_path = "/home/user/validate_auth_keys.sh"
    assert os.path.isfile(script_path), f"Filter script not found at {script_path}"

    clean_dir = Path("/app/corpora/clean")
    evil_dir = Path("/app/corpora/evil")

    assert clean_dir.is_dir(), "Clean corpus directory missing."
    assert evil_dir.is_dir(), "Evil corpus directory missing."

    clean_modified = []
    for clean_file in clean_dir.iterdir():
        if clean_file.is_file():
            original_content = clean_file.read_text()
            result = run_filter(script_path, original_content)
            if result.stdout != original_content:
                clean_modified.append(clean_file.name)

    evil_bypassed = []
    for evil_file in evil_dir.iterdir():
        if evil_file.is_file():
            original_content = evil_file.read_text()
            result = run_filter(script_path, original_content)
            if result.stdout.strip() != "":
                evil_bypassed.append(evil_file.name)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(list(evil_dir.iterdir()))} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(list(clean_dir.iterdir()))} clean modified: {', '.join(clean_modified)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_validate_auth_keys_filter_generated_cases():
    """Exercise filtering on fresh lines not present in the public corpora."""
    script_path = "/home/user/validate_auth_keys.sh"
    assert os.path.isfile(script_path), f"Filter script not found at {script_path}"

    def blob():
        return base64.b64encode(secrets.token_bytes(32)).decode("ascii")

    tag = secrets.token_hex(12)
    accepted = [
        f"ssh-ed25519 {blob()} generated-ed-{tag}",
        f"ecdsa-sha2-nistp256 {blob()} generated-ecdsa-{tag}",
        f"restrict ssh-ed25519 {blob()} restricted-{tag}",
        f'restrict,command="/usr/bin/rsync" ssh-ed25519 {blob()} backup-{tag}',
        f'command="/opt/tools/backup_{tag}" ecdsa-sha2-nistp256 {blob()} command-{tag}',
    ]
    rejected = [
        f"ssh-rsa {blob()} weak-rsa-{tag}",
        f"ssh-dss {blob()} weak-dss-{tag}",
        f'command="/usr/bin/true|/bin/sh" ssh-ed25519 {blob()} pipe-{tag}',
        f'command="/usr/bin/true&/bin/sh" ssh-ed25519 {blob()} amp-{tag}',
        f'command="/usr/bin/echo $HOME" ssh-ed25519 {blob()} dollar-{tag}',
        f'command="`/bin/sh`" ecdsa-sha2-nistp256 {blob()} backtick-{tag}',
        f'command="/usr/bin/true;/bin/sh" ssh-ed25519 {blob()} semicolon-{tag}',
        f'environment="SAFE_NAME=value" ssh-ed25519 {blob()} environment-{tag}',
    ]

    # Check each line independently, then check that the script correctly handles
    # a mixed multi-line authorized_keys stream while preserving accepted bytes.
    for line in accepted:
        result = run_filter(script_path, line + "\n")
        assert result.returncode == 0, result.stderr
        assert result.stdout == line + "\n", f"secure generated line was modified or rejected: {line!r}"

    for line in rejected:
        result = run_filter(script_path, line + "\n")
        assert result.returncode == 0, result.stderr
        assert result.stdout == "", f"unsafe generated line bypassed the filter: {line!r}"

    mixed = []
    for index in range(max(len(accepted), len(rejected))):
        if index < len(rejected):
            mixed.append(rejected[index])
        if index < len(accepted):
            mixed.append(accepted[index])
    result = run_filter(script_path, "\n".join(mixed) + "\n")
    assert result.returncode == 0, result.stderr
    assert result.stdout == "".join(line + "\n" for line in accepted)

    empty = run_filter(script_path, "")
    assert empty.returncode == 0, empty.stderr
    assert empty.stdout == ""


def test_admin_key_generated():
    """Verify that the admin ed25519 key was generated correctly with proper permissions."""
    key_path = "/home/user/admin_key"
    assert os.path.isfile(key_path), f"Admin key not found at {key_path}"

    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Expected permissions 600 for {key_path}, got {oct(perms)}"

    content = Path(key_path).read_text()
    assert "BEGIN OPENSSH PRIVATE KEY" in content, "Key does not appear to be a valid OpenSSH private key."

    result = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", key_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Key validation failed (might have a passphrase or be invalid). Error: {result.stderr}"
    assert "ssh-ed25519" in result.stdout, "Generated key is not an ed25519 key."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
