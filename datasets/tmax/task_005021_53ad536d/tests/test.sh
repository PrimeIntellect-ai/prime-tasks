#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import subprocess
import tempfile
import pytest

FORGE_SOURCE = "/home/user/forge.c"
FORGE_BINARY = "/home/user/forge"
AUTH_PARSER = "/home/user/auth_parser"
REPORT = "/home/user/audit_report.txt"


def read_report():
    with open(REPORT, "r") as f:
        return f.read().splitlines()


def run_program(path, stdin=None):
    return subprocess.run(
        [path],
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )


def assert_forge_behavior(path, expected_token):
    result = run_program(path)
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; stderr: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    expected_bytes = expected_token.encode("utf-8")
    assert result.stdout == expected_bytes, (
        "Forge must print exactly the forged token with no trailing newline. "
        f"Expected {expected_bytes!r}, got {result.stdout!r}."
    )

    parser_result = run_program(AUTH_PARSER, stdin=result.stdout)
    assert parser_result.returncode == 0, (
        f"auth_parser exited with status {parser_result.returncode}; stderr: "
        f"{parser_result.stderr.decode('utf-8', errors='replace')}"
    )
    return parser_result.stdout


def test_forge_c_exists():
    path = "/home/user/forge.c"
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_forge_executable_exists():
    path = "/home/user/forge"
    assert os.path.exists(path), f"Executable {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"Executable {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_audit_report_exists_and_content():
    path = "/home/user/audit_report.txt"
    assert os.path.exists(path), f"Audit report {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) == 3, f"Audit report should have exactly 3 lines, found {len(lines)}."

    token = lines[0]
    checksum = lines[1]
    output = lines[2]

    # Validate token format
    parts = token.split(":")
    assert len(parts) >= 3, "Forged token must have at least 3 colon-separated parts (ALG:USERNAME:ROLE)."

    alg = parts[0]
    user = parts[1]
    role = parts[2]

    assert alg.lower() == "none", f"Algorithm in token must be 'none' (case-insensitive), got '{alg}'."
    assert user == "<script>audit_bypass</script>", f"Username in token must be '<script>audit_bypass</script>', got '{user}'."
    assert role == "admin", f"Role in token must be 'admin', got '{role}'."

    # Validate checksum
    expected_checksum = hashlib.sha256(token.encode('utf-8')).hexdigest()
    assert checksum.lower() == expected_checksum, f"Checksum on line 2 is incorrect. Expected {expected_checksum}, got {checksum}."

    # Validate output
    expected_output = "AUDIT_LOG: Access Granted to admin user <script>audit_bypass</script>"
    assert output == expected_output, f"Output on line 3 is incorrect. Expected '{expected_output}', got '{output}'."


def test_source_compiles_and_artifacts_execute_through_parser():
    token, checksum, reported_output = read_report()

    # Execute the submitted /home/user/forge artifact itself.
    installed_parser_output = assert_forge_behavior(FORGE_BINARY, token)
    assert installed_parser_output == (reported_output + "\n").encode("utf-8"), (
        "Audit report line 3 does not match the exact output produced by piping "
        "/home/user/forge into /home/user/auth_parser."
    )

    # Independently compile forge.c and exercise the resulting program, ensuring
    # the required behavior is implemented by the submitted C source as well.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_forge = os.path.join(tmpdir, "forge")
        compile_result = subprocess.run(
            ["gcc", FORGE_SOURCE, "-o", rebuilt_forge],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "forge.c failed to compile with gcc: "
            + compile_result.stderr.decode("utf-8", errors="replace")
        )
        rebuilt_parser_output = assert_forge_behavior(rebuilt_forge, token)
        assert rebuilt_parser_output == (reported_output + "\n").encode("utf-8"), (
            "The output produced by piping the compiled forge.c program into "
            "/home/user/auth_parser does not match audit report line 3."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
