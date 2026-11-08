#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest


def test_ssh_key_rotated():
    private_key_path = "/home/user/.ssh/id_ed25519_rotated"

    # Original assertions: the private key exists and is Ed25519.
    assert os.path.exists(private_key_path), f"Private key not found at {private_key_path}"
    assert os.path.isfile(private_key_path), f"{private_key_path} is not a file"

    try:
        result = subprocess.run(
            ["ssh-keygen", "-l", "-f", private_key_path],
            capture_output=True,
            text=True,
            check=True,
        )
        assert "ED25519" in result.stdout.upper(), (
            f"Key at {private_key_path} is not an ED25519 key. Output: {result.stdout}"
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to inspect the SSH key with ssh-keygen. Error: {e.stderr}")

    # The required public half must exist and match the private key. Supplying an
    # empty passphrase must work, which also rejects an encrypted private key.
    public_key_path = private_key_path + ".pub"
    assert os.path.exists(public_key_path), f"Public key not found at {public_key_path}"
    assert os.path.isfile(public_key_path), f"{public_key_path} is not a file"

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", private_key_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert derived.returncode == 0, (
        "The private key could not be read with an empty passphrase: " + derived.stderr
    )

    with open(public_key_path, "r", encoding="utf-8") as f:
        public_fields = f.read().strip().split()
    derived_fields = derived.stdout.strip().split()
    assert len(public_fields) >= 2, "The public key file is malformed"
    assert len(derived_fields) >= 2, "Could not derive a public key from the private key"
    assert public_fields[0] == "ssh-ed25519", "The public key is not Ed25519"
    assert public_fields[:2] == derived_fields[:2], (
        "The public key does not match id_ed25519_rotated"
    )


def test_redacted_auth_log():
    redacted_log_path = "/home/user/redacted_auth.log"

    # Original assertions and exact fixture comparison.
    assert os.path.exists(redacted_log_path), f"Redacted log not found at {redacted_log_path}"
    assert os.path.isfile(redacted_log_path), f"{redacted_log_path} is not a file"

    expected_content = """Jan 15 10:00:01 server sshd[1234]: Failed password for invalid user [REDACTED] from 192.168.1.100 port 50000 ssh2
Jan 15 10:05:00 server sshd[1235]: Failed password for [REDACTED] from 10.0.0.5 port 50001 ssh2
Jan 15 10:10:00 server sshd[1236]: Accepted publickey for alice from 192.168.1.50 port 50002 ssh2
Jan 15 10:15:00 server sshd[1237]: Invalid user bob from 10.0.0.6
Jan 15 10:20:00 server sshd[1238]: Failed password for secret_password123 from 10.0.0.7 port 50003 ssh2
Jan 15 10:25:00 server sshd[1239]: Invalid user [REDACTED] from 192.168.1.101
"""

    with open(redacted_log_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content == expected_content, (
        "The redacted auth log does not match the expected output. "
        "Ensure all redaction rules are correctly applied."
    )


def _expected_redaction(data):
    patterns = [
        re.compile(r"Failed password for invalid user (\S+) "),
        re.compile(r"Failed password for (\S+) "),
        re.compile(r"Invalid user (\S+) "),
    ]
    output = []
    for line in data.splitlines(keepends=True):
        for pattern in patterns:
            match = pattern.search(line)
            if match:
                username = match.group(1)
                if username == "root" or "@" in username:
                    line = line[:match.start(1)] + "[REDACTED]" + line[match.end(1):]
                break
        output.append(line)
    return "".join(output)


def test_go_program_executes_and_generalizes():
    source_path = "/home/user/process_logs.go"
    auth_path = "/home/user/auth.log"
    output_path = "/home/user/redacted_auth.log"

    assert os.path.exists(source_path), f"Go source not found at {source_path}"
    assert os.path.isfile(source_path), f"{source_path} is not a file"

    token = secrets.token_hex(12)
    email = f"person-{token}@example.test"
    safe_user = f"safe_{token}"
    dynamic_input = "".join([
        f"Feb 02 01:00:00 host sshd[1]: Failed password for invalid user {email} from 10.1.1.1 port 1 ssh2\n",
        "Feb 02 01:00:01 host sshd[2]: Failed password for invalid user root from 10.1.1.2 port 2 ssh2\n",
        f"Feb 02 01:00:02 host sshd[3]: Failed password for {email} from 10.1.1.3 port 3 ssh2\n",
        "Feb 02 01:00:03 host sshd[4]: Failed password for root from 10.1.1.4 port 4 ssh2\n",
        f"Feb 02 01:00:04 host sshd[5]: Invalid user {email} from 10.1.1.5\n",
        "Feb 02 01:00:05 host sshd[6]: Invalid user root from 10.1.1.6\n",
        f"Feb 02 01:00:06 host sshd[7]: Failed password for invalid user {safe_user} from 10.1.1.7 port 7 ssh2\n",
        f"Feb 02 01:00:07 host sshd[8]: Failed password for {safe_user} from 10.1.1.8 port 8 ssh2\n",
        f"Feb 02 01:00:08 host sshd[9]: Invalid user {safe_user} from 10.1.1.9\n",
        f"Feb 02 01:00:09 host sshd[10]: Accepted publickey for {email} from 10.1.1.10 port 10 ssh2\n",
        "Feb 02 01:00:10 host sshd[11]: Accepted publickey for root from 10.1.1.11 port 11 ssh2\n",
        f"unrelated line containing {email} and root must remain unchanged\n",
    ])
    expected = _expected_redaction(dynamic_input)

    with open(auth_path, "rb") as f:
        original_auth = f.read()
    with open(output_path, "rb") as f:
        original_output = f.read()

    try:
        with open(auth_path, "w", encoding="utf-8", newline="") as f:
            f.write(dynamic_input)
        os.unlink(output_path)

        result = subprocess.run(
            ["go", "run", source_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
            env={**os.environ, "HOME": "/home/user"},
        )
        assert result.returncode == 0, (
            f"process_logs.go failed to compile or run. stdout: {result.stdout} stderr: {result.stderr}"
        )
        assert os.path.isfile(output_path), "The Go program did not create redacted_auth.log"
        with open(output_path, "r", encoding="utf-8", newline="") as f:
            actual = f.read()
        assert actual == expected, "The Go program failed the generated redaction cases"
    finally:
        with open(auth_path, "wb") as f:
            f.write(original_auth)
        with open(output_path, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
