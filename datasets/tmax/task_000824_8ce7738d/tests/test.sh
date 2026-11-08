#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import pytest

def test_audit_log_contents():
    log_path = "/home/user/audit_log.txt"
    assert os.path.isfile(log_path), f"Audit log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "/home/user/uploads/backup/config.key",
        "/home/user/uploads/id_rsa_leaked"
    ]

    assert lines == expected_lines, f"Audit log contents are incorrect. Expected {expected_lines}, got {lines}"

def test_redacted_files():
    files_to_check = [
        ("/home/user/uploads/id_rsa_leaked", "-----BEGIN OPENSSH PRIVATE KEY-----\n[REDACTED]\n-----END OPENSSH PRIVATE KEY-----\n", 0o600),
        ("/home/user/uploads/backup/config.key", "Some config data here.\n-----BEGIN OPENSSH PRIVATE KEY-----\n[REDACTED]\n-----END OPENSSH PRIVATE KEY-----\nEnd of config data.\n", 0o600)
    ]

    for file_path, expected_content, expected_perm in files_to_check:
        assert os.path.isfile(file_path), f"File {file_path} does not exist."

        st = os.stat(file_path)
        assert stat.S_IMODE(st.st_mode) == expected_perm, f"Permissions for {file_path} should be {oct(expected_perm)}."

        with open(file_path, "r") as f:
            content = f.read()

        assert content == expected_content, f"Content for {file_path} is incorrect. Got:\n{content}"

def test_untouched_files():
    files_to_check = [
        ("/home/user/uploads/normal.txt", 0o644),
        ("/home/user/uploads/images/logo.png", 0o644)
    ]

    for file_path, expected_perm in files_to_check:
        assert os.path.isfile(file_path), f"File {file_path} does not exist."

        st = os.stat(file_path)
        assert stat.S_IMODE(st.st_mode) == expected_perm, f"Permissions for {file_path} should be {oct(expected_perm)}."

        if file_path == "/home/user/uploads/normal.txt":
            with open(file_path, "r") as f:
                content = f.read()
            assert "Just a normal text file uploaded by a user." in content, f"Content of {file_path} was altered."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ ! -f /home/user/audit_keys.go ] || [ -L /home/user/audit_keys.go ]; then
    echo "Missing regular Go source file: /home/user/audit_keys.go" >&2
    status=1
fi

workdir=$(mktemp -d /tmp/audit-verifier.XXXXXX)
backup_ready=0
saved_log=0
cleanup() {
    if [ "$backup_ready" -eq 1 ]; then
        rm -rf /home/user/uploads
        rm -f /home/user/audit_log.txt
        mv "$workdir/original_uploads" /home/user/uploads 2>/dev/null || true
        if [ "$saved_log" -eq 1 ]; then
            mv "$workdir/original_audit_log.txt" /home/user/audit_log.txt 2>/dev/null || true
        fi
    fi
    rm -rf "$workdir"
}
trap cleanup EXIT

if [ "$status" -eq 0 ]; then
    mv /home/user/uploads "$workdir/original_uploads" || status=1
    if [ "$status" -eq 0 ]; then
        backup_ready=1
        if [ -e /home/user/audit_log.txt ]; then
            mv /home/user/audit_log.txt "$workdir/original_audit_log.txt" || status=1
            [ "$status" -eq 0 ] && saved_log=1
        fi
    fi
fi

if [ "$status" -eq 0 ]; then
    python3 - "$workdir/expected.json" << 'PY_SETUP' || status=1
import json
import os
import secrets
import stat
import sys

manifest_path = sys.argv[1]
base = "/home/user/uploads"
token = secrets.token_hex(10)
header = "-----BEGIN OPENSSH PRIVATE KEY-----"
footer = "-----END OPENSSH PRIVATE KEY-----"

nested = os.path.join(base, "nested_" + token, "deeper_" + token)
os.makedirs(nested, mode=0o755)

cases = {}

path1 = os.path.join(base, "upload_" + token + ".dat")
original1 = "metadata before\n" + header + "\n" + secrets.token_hex(31) + "\n" + footer + "\nmetadata after\n"
expected1 = "metadata before\n" + header + "\n[REDACTED]\n" + footer + "\nmetadata after\n"
cases[path1] = {"original": original1, "expected": expected1, "mode": 0o666, "matched": True}

path2 = os.path.join(nested, "two_keys_" + token)
original2 = ("prefix\n" + header + "\n" + secrets.token_hex(19) + "\n" + footer +
             "\nbetween\n" + header + "\n" + secrets.token_hex(23) + "\n" + footer + "\nsuffix\n")
expected2 = ("prefix\n" + header + "\n[REDACTED]\n" + footer +
             "\nbetween\n" + header + "\n[REDACTED]\n" + footer + "\nsuffix\n")
cases[path2] = {"original": original2, "expected": expected2, "mode": 0o777, "matched": True}

path3 = os.path.join(base, "ordinary_" + token + ".txt")
original3 = "ordinary randomized content " + secrets.token_hex(24) + "\n"
cases[path3] = {"original": original3, "expected": original3, "mode": 0o640, "matched": False}

path4 = os.path.join(nested, "public_key_" + token)
original4 = "-----BEGIN OPENSSH PUBLIC KEY-----\n" + secrets.token_hex(20) + "\n-----END OPENSSH PUBLIC KEY-----\n"
cases[path4] = {"original": original4, "expected": original4, "mode": 0o644, "matched": False}

for path, case in cases.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(case["original"])
    os.chmod(path, case["mode"])

manifest = {
    "cases": cases,
    "expected_log": sorted(path for path, case in cases.items() if case["matched"]),
}
with open(manifest_path, "w") as f:
    json.dump(manifest, f)
PY_SETUP
fi

if [ "$status" -eq 0 ]; then
    timeout 60s go run /home/user/audit_keys.go 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    python3 - "$workdir/expected.json" << 'PY_CHECK' || status=1
import json
import os
import stat
import sys

with open(sys.argv[1], "r") as f:
    manifest = json.load(f)

for path, case in manifest["cases"].items():
    assert os.path.isfile(path), f"Audited fixture disappeared: {path}"
    with open(path, "r") as f:
        actual = f.read()
    assert actual == case["expected"], f"Incorrect content after auditing {path}: {actual!r}"
    actual_mode = stat.S_IMODE(os.stat(path).st_mode)
    expected_mode = 0o600 if case["matched"] else case["mode"]
    assert actual_mode == expected_mode, f"Incorrect mode for {path}: {oct(actual_mode)}, expected {oct(expected_mode)}"

log_path = "/home/user/audit_log.txt"
assert os.path.isfile(log_path), "The dynamically exercised run did not create audit_log.txt"
with open(log_path, "r") as f:
    log_lines = f.read().splitlines()
assert log_lines == manifest["expected_log"], f"Dynamic audit log mismatch: expected {manifest['expected_log']}, got {log_lines}"
PY_CHECK
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

exit 0
