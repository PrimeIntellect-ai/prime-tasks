#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import string
import subprocess
import tempfile

REPORT_PATH = "/home/user/audit_report.txt"
SOURCE_PATH = "/home/user/secure_net_helper.c"
BINARY_PATH = "/home/user/secure_net_helper"


def expected_output(args):
    return "ACCESS GRANTED\n" if len(args) == 1 and args[0] == "admin" else "ACCESS DENIED\n"


def run_helper(path, args):
    result = subprocess.run([path, *args], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"{path} exited with status {result.returncode} for arguments {args!r}"
    assert result.stdout == expected_output(args), (
        f"Unexpected stdout from {path} for arguments {args!r}: {result.stdout!r}"
    )


def test_audit_report():
    assert os.path.exists(REPORT_PATH), f"Audit report not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        raw_content = f.read()

    content = raw_content.splitlines()
    expected_token = "Token: B4ckd00r_T0k3n_9921"
    expected_suid = "SUID: /home/user/old_backup_tool"

    assert expected_token in content, f"Expected '{expected_token}' in {REPORT_PATH}"
    assert expected_suid in content, f"Expected '{expected_suid}' in {REPORT_PATH}"
    assert raw_content == expected_token + "\n" + expected_suid + "\n", (
        f"{REPORT_PATH} does not have the required exact two-line format"
    )


def test_secure_net_helper_permissions():
    assert os.path.exists(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file"

    st = os.stat(BINARY_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o500, f"Permissions for {BINARY_PATH} are {oct(perms)}, expected 0o500"


def test_secure_net_helper_is_built_from_valid_c_source():
    assert os.path.exists(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must be a regular source file"

    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable"

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "secure_net_helper")
        compile_result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert compile_result.returncode == 0, (
            f"{SOURCE_PATH} does not compile successfully as C: {compile_result.stderr}"
        )

        random_values = [
            "probe_" + secrets.token_hex(16),
            "guest_" + secrets.token_hex(16),
            "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(31)),
        ]
        cases = [
            [],
            ["admin"],
            ["hacker"],
            ["admin", "extra"],
            [""],
            *[[value] for value in random_values],
            [random_values[0], random_values[1]],
            ["admin", random_values[2], "extra"],
        ]

        for args in cases:
            run_helper(rebuilt, args)
            run_helper(BINARY_PATH, args)


def test_secure_net_helper_functionality():
    assert os.path.exists(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    run_helper(BINARY_PATH, ["admin"])
    run_helper(BINARY_PATH, ["hacker"])
    run_helper(BINARY_PATH, [])
    run_helper(BINARY_PATH, ["admin", "extra"])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
