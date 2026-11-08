#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

SOURCE = "/home/user/redactor.c"
EXECUTABLE = "/home/user/redactor"
SAFE_LOGS = "/home/user/safe_logs.txt"
APP_LOGS = "/home/user/app_logs.txt"

EXPECTED_APP_OUTPUT = """[INFO] Server started on port 8080.
[DEBUG] User authentication attempt.
[WARN] Deprecated auth token found: [REDACTED]
[INFO] Authentication successful.
[DEBUG] Payload metadata: <SECRET:001122334455>
[WARN] Deprecated auth token found: [REDACTED]
[INFO] Connection closed.
"""


def run_redactor(path, data):
    result = subprocess.run(
        [path], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; "
        f"stderr={result.stderr.decode('utf-8', 'replace')!r}"
    )
    return result.stdout


def valid_secret(hex_text):
    if len(hex_text) < 10 or len(hex_text) % 2:
        return False
    try:
        encrypted = bytes.fromhex(hex_text)
    except ValueError:
        return False
    return any(
        bytes(byte ^ key for byte in encrypted[:5]) == b"PASS_"
        for key in range(256)
    )


def expected_redaction(data):
    text = data.decode("ascii")
    pattern = re.compile(r"<SECRET:([0-9a-f]+)>")
    return pattern.sub(
        lambda match: "[REDACTED]" if valid_secret(match.group(1)) else match.group(0),
        text,
    ).encode("ascii")


def encrypted_credential(plaintext, key):
    return bytes(byte ^ key for byte in plaintext).hex()


def test_redactor_c_exists_and_seccomp():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "PR_SET_SECCOMP" in content, "PR_SET_SECCOMP not found in redactor.c"
    assert "SECCOMP_MODE_STRICT" in content, "SECCOMP_MODE_STRICT not found in redactor.c"
    assert re.search(
        r"prctl\s*\(\s*PR_SET_SECCOMP\s*,\s*SECCOMP_MODE_STRICT\s*\)", content
    ), "redactor.c does not call prctl(PR_SET_SECCOMP, SECCOMP_MODE_STRICT)"


def test_redactor_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not an ELF executable."


def test_safe_logs_content():
    assert os.path.isfile(SAFE_LOGS), f"{SAFE_LOGS} does not exist."
    with open(SAFE_LOGS, "r") as f:
        actual_content = f.read()
    assert actual_content.strip() == EXPECTED_APP_OUTPUT.strip(), (
        f"Content of {SAFE_LOGS} does not match expected output exactly."
    )


def test_submitted_executable_processes_fixture():
    with open(APP_LOGS, "rb") as f:
        app_input = f.read()
    assert run_redactor(EXECUTABLE, app_input) == EXPECTED_APP_OUTPUT.encode()


def test_source_builds_and_both_binaries_handle_derived_inputs(tmp_path):
    rebuilt = str(tmp_path / "rebuilt-redactor")
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False
    )
    assert build.returncode == 0, (
        "redactor.c did not compile: " + build.stderr.decode("utf-8", "replace")
    )

    key1 = secrets.randbelow(256)
    key2 = secrets.randbelow(256)
    valid1 = encrypted_credential(b"PASS_" + secrets.token_bytes(11), key1)
    valid2 = encrypted_credential(b"PASS_admin_" + secrets.token_bytes(7), key2)

    while True:
        invalid = secrets.token_bytes(14).hex()
        if not valid_secret(invalid):
            break

    cases = [
        b"ordinary text passes through unchanged\n",
        (f"before <SECRET:{valid1}> after\n").encode(),
        (f"<SECRET:{invalid}>\n").encode(),
        (f"A<SECRET:{valid1}>B<SECRET:{invalid}>C<SECRET:{valid2}>D\n").encode(),
        (f"<SECRET:{valid2}>").encode(),
        b"malformed <SECRET:123> and <SECRET:xyz> and <SECRET:> stay intact\n",
        (b"x" * 5000) + (f"<SECRET:{valid1}>tail\n").encode(),
    ]

    for data in cases:
        expected = expected_redaction(data)
        assert run_redactor(EXECUTABLE, data) == expected
        assert run_redactor(rebuilt, data) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
