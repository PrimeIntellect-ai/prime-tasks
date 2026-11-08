#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile


def get_expected_fingerprint():
    """Derive the expected SHA-1 fingerprint from server.pem."""
    pem_path = "/home/user/server.pem"
    assert os.path.exists(pem_path), f"Missing required file: {pem_path}"

    result = subprocess.run(
        ['openssl', 'x509', '-noout', '-fingerprint', '-sha1', '-in', pem_path],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip().split('=')[1]


def token_for(username):
    key = b"sUp3r_s3cr3t_k3y"
    msg = username.encode('utf-8')
    return bytes([m ^ key[i % len(key)] for i, m in enumerate(msg)]).hex()


def test_findings_log_contents():
    log_path = "/home/user/findings.log"
    assert os.path.exists(log_path), f"Missing file: {log_path}"

    with open(log_path, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"findings.log must contain exactly 2 lines, but found {len(lines)} lines."

    expected_port = "9443"
    assert lines[0].strip() == expected_port, f"Line 1 of findings.log is incorrect. Expected '{expected_port}', got '{lines[0]}'."

    expected_fp = get_expected_fingerprint()
    assert lines[1].strip() == expected_fp, f"Line 2 of findings.log is incorrect. Expected '{expected_fp}', got '{lines[1]}'."


def test_exploit_py_execution_and_output():
    script_path = "/home/user/exploit.py"
    assert os.path.exists(script_path), f"Missing file: {script_path}"
    assert os.path.isfile(script_path), f"exploit.py is not a regular file: {script_path}"

    result = subprocess.run(['python3', script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"exploit.py failed to execute successfully. Stderr: {result.stderr}"

    output = result.stdout.strip()
    expected_token = token_for("admin_root_system")
    assert output == expected_token, f"Output of exploit.py is incorrect. Expected '{expected_token}', got '{output}'."


def test_exploit_dynamically_generates_token():
    script_path = "/home/user/exploit.py"
    with open(script_path, 'r', encoding='utf-8') as f:
        source = f.read()

    marker = "admin_root_system"
    assert marker in source, "exploit.py must generate its token from the requested username, not print a precomputed token."

    for _ in range(2):
        # Keep the same input length while using an unpredictable username.
        username = "audit_" + ''.join(secrets.choice(string.ascii_lowercase) for _ in range(11))
        transformed = source.replace(marker, username)

        fd, temp_path = tempfile.mkstemp(prefix='.verifier_exploit_', suffix='.py', dir='/home/user')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                f.write(transformed)

            result = subprocess.run(['python3', temp_path], capture_output=True, text=True)
            assert result.returncode == 0, f"exploit.py did not dynamically handle the username. Stderr: {result.stderr}"
            expected = token_for(username)
            assert result.stdout.strip() == expected, (
                "exploit.py appears to print a precomputed token instead of dynamically "
                f"generating one for the username; expected '{expected}', got '{result.stdout.strip()}'."
            )
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
