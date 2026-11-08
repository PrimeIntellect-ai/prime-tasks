#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import tempfile
import pytest

@pytest.fixture(scope="session", autouse=True)
def compile_and_run_forge():
    source_path = "/home/user/forge.c"
    payload_path = "/home/user/payload.bin"

    assert os.path.exists(source_path), f"File {source_path} is missing. You must write your payload generator in C."
    assert os.path.isfile(source_path), f"Path {source_path} is not a file."

    with tempfile.TemporaryDirectory(prefix="forge-build-") as build_dir:
        executable_path = os.path.join(build_dir, "forge")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", executable_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"Failed to compile {source_path} as C. stdout: {compile_result.stdout} "
            f"stderr: {compile_result.stderr}"
        )

        # The submitted C generator, rather than a pre-existing payload, must
        # create the ticket checked by the remaining tests.
        if os.path.lexists(payload_path):
            os.unlink(payload_path)

        run_result = subprocess.run(
            [executable_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            f"Compiled forge program exited with code {run_result.returncode}. "
            f"stdout: {run_result.stdout} stderr: {run_result.stderr}"
        )
        assert os.path.exists(payload_path), (
            f"Executing the compiled {source_path} did not generate {payload_path}."
        )
        assert os.path.isfile(payload_path), f"Path {payload_path} is not a file."


def test_cwe_flaw_txt():
    path = "/home/user/cwe_flaw.txt"
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip().upper()

    allowed_cwes = ["CWE-327", "CWE-345", "CWE-347"]
    found = any(cwe in content for cwe in allowed_cwes)
    assert found, f"File {path} does not contain an acceptable CWE ID (e.g., CWE-327, CWE-345, or CWE-347)."
    assert content in allowed_cwes, f"File {path} must contain exactly one acceptable CWE ID."


def test_forge_c_exists():
    path = "/home/user/forge.c"
    assert os.path.exists(path), f"File {path} is missing. You must write your payload generator in C."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_payload_bin_exists_and_size():
    path = "/home/user/payload.bin"
    assert os.path.exists(path), f"File {path} is missing. You must generate the forged ticket."
    assert os.path.isfile(path), f"Path {path} is not a file."

    size = os.path.getsize(path)
    assert size == 36, f"File {path} is {size} bytes, but expected exactly 36 bytes."


def test_vuln_auth_bypass():
    binary_path = "/home/user/vuln_auth"
    payload_path = "/home/user/payload.bin"

    assert os.path.exists(binary_path), f"Binary {binary_path} is missing."
    assert os.path.exists(payload_path), f"Payload {payload_path} is missing."

    result = subprocess.run([binary_path, payload_path], capture_output=True, text=True)

    assert result.returncode == 0, f"Execution failed with return code {result.returncode}. Output: {result.stdout}"
    assert "Access Granted: admin" in result.stdout, f"Expected 'Access Granted: admin' in output, got: {result.stdout}"


def test_payload_contents():
    path = "/home/user/payload.bin"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "rb") as f:
        data = f.read()

    assert len(data) == 36, "Payload size is incorrect."

    username_bytes = data[0:16]
    role_bytes = data[16:32]

    # Extract string up to first null byte
    username = username_bytes.split(b'\0')[0].decode('ascii', errors='ignore')
    role = role_bytes.split(b'\0')[0].decode('ascii', errors='ignore')

    assert username == "attacker", f"Expected username 'attacker', got '{username}'"
    assert role == "admin", f"Expected role 'admin', got '{role}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
