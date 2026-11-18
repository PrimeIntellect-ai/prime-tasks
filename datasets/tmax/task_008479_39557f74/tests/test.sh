#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64
import hmac
import hashlib
import subprocess
import tempfile
from pathlib import Path


def get_expected_token():
    """Derive the expected token based on the truth data."""
    user = base64.urlsafe_b64encode(b"admin").rstrip(b'=')
    role = base64.urlsafe_b64encode(b"superuser").rstrip(b'=')
    message = user + b"." + role
    key = b"S3cur1ty_H@rdc0d3d_99!"
    mac = hmac.new(key, message, hashlib.sha256).digest()
    mac_b64 = base64.urlsafe_b64encode(mac).rstrip(b'=')
    return (message + b"." + mac_b64).decode("utf-8")


def test_flag_file_correct():
    """Verify that the flag file exists and contains the correct flag."""
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"Flag file {flag_path} does not exist."

    with open(flag_path, "r") as f:
        content = f.read().strip()

    expected_flag = "FLAG{h4rdc0d3d_s3cr3ts_r_b4d}"
    assert content == expected_flag, f"Flag file content '{content}' does not match expected '{expected_flag}'."


def test_forged_token_file_correct():
    """Verify that the forged token file exists and contains the correct token."""
    token_path = "/home/user/forged_token.txt"
    assert os.path.isfile(token_path), f"Token file {token_path} does not exist."

    with open(token_path, "r") as f:
        content = f.read().strip()

    expected_token = get_expected_token()
    assert content == expected_token, f"Token file content '{content}' does not match expected '{expected_token}'."


def test_forge_go_exists_and_non_empty():
    """Verify that the forge.go script exists and has content."""
    script_path = "/home/user/forge.go"
    assert os.path.isfile(script_path), f"Go script {script_path} does not exist."
    assert os.path.getsize(script_path) > 0, f"Go script {script_path} is empty."


def test_forge_go_compiles_runs_and_token_works_with_admin_cli():
    """Compile and execute forge.go, then use its generated token with the supplied CLI."""
    source = "/home/user/forge.go"
    token_path = Path("/home/user/forged_token.txt")
    expected_token = get_expected_token()
    expected_flag = "FLAG{h4rdc0d3d_s3cr3ts_r_b4d}"

    with tempfile.TemporaryDirectory(prefix="verify_forge_") as temp_dir:
        executable = os.path.join(temp_dir, "forge")
        build = subprocess.run(
            ["go", "build", "-o", executable, source],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"forge.go failed to compile: {build.stderr}"

        backup_path = Path(temp_dir) / "submitted_forged_token.txt"
        os.replace(token_path, backup_path)
        generated_file_content = None
        try:
            run = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert run.returncode == 0, f"Compiled forge.go failed to run: {run.stderr}"

            stdout_token = run.stdout.strip()
            if token_path.is_file():
                generated_file_content = token_path.read_text().strip()

            produced_tokens = [value for value in (stdout_token, generated_file_content) if value]
            assert produced_tokens, "forge.go produced no token on stdout or in /home/user/forged_token.txt."
            assert all(value == expected_token for value in produced_tokens), "forge.go generated an incorrect token."
            runtime_token = produced_tokens[0]
        finally:
            if token_path.exists():
                token_path.unlink()
            os.replace(backup_path, token_path)

        cli = subprocess.run(
            ["/home/user/audit/admin_cli", "--token", runtime_token, "--action", "get_flag"],
            cwd="/home/user/audit",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert cli.returncode == 0, f"admin_cli rejected the generated token: {cli.stdout}{cli.stderr}"
        assert cli.stdout.strip() == expected_flag, f"admin_cli did not return the expected flag: {cli.stdout!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
