#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import ast
import base64
import hashlib
import secrets
import subprocess
from pathlib import Path


def test_c2_address_txt():
    """Verify that the c2_address.txt file contains the correct decoded IP and port."""
    file_path = "/home/user/c2_address.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = "198.51.100.45:4444"
    assert content == expected, f"Expected {file_path} to contain '{expected}', but got '{content}'."


def test_firewall_block_sh():
    """Verify that the firewall_block.sh file contains the correct iptables rule."""
    file_path = "/home/user/firewall_block.sh"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        # Read the file and filter out empty lines
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 1, f"Expected exactly one non-empty line in {file_path}, but found {len(lines)}."

    expected_rule = "iptables -A OUTPUT -d 198.51.100.45 -p tcp --dport 4444 -j DROP"
    assert lines[0] == expected_rule, f"Expected rule '{expected_rule}', but got '{lines[0]}'."


def test_extract_c2_py():
    """Verify that the extract_c2.py script exists and is a valid Python file."""
    file_path = "/home/user/extract_c2.py"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        source = f.read()

    try:
        ast.parse(source)
    except SyntaxError as e:
        assert False, f"The file {file_path} contains invalid Python syntax: {e}"


def test_extract_c2_executes_and_verifies_hash():
    """Execute the submitted script on derived valid and invalid cmdline data."""
    script = Path("/home/user/extract_c2.py")
    cmdline = Path("/home/user/evidence/proc_9999/cmdline")
    output = Path("/home/user/c2_address.txt")

    original_cmdline = cmdline.read_bytes()
    original_output = output.read_bytes() if output.exists() else None

    def remove_output():
        if output.exists() or output.is_symlink():
            output.unlink()

    try:
        octet = secrets.randbelow(253) + 1
        port = secrets.randbelow(50000) + 10000
        decoded = f"203.0.113.{octet}:{port}"
        payload = base64.b64encode(decoded.encode("ascii")).decode("ascii")
        digest = hashlib.sha256(decoded.encode("ascii")).hexdigest()
        cmdline.write_bytes(
            b"python3\0/tmp/kworker.py\0--c2-payload\0"
            + payload.encode("ascii")
            + b"\0--verify\0"
            + digest.encode("ascii")
            + b"\0"
        )
        remove_output()

        result = subprocess.run(
            ["python3", str(script)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"extract_c2.py failed on a valid cmdline (exit {result.returncode}): "
            f"{result.stderr}"
        )
        assert output.is_file(), "extract_c2.py did not generate c2_address.txt"
        assert output.read_text().strip() == decoded, (
            "extract_c2.py did not decode and write the dynamically generated C2 address"
        )

        wrong_digest = hashlib.sha256((decoded + "-wrong").encode("ascii")).hexdigest()
        cmdline.write_bytes(
            b"python3\0/tmp/kworker.py\0--c2-payload\0"
            + payload.encode("ascii")
            + b"\0--verify\0"
            + wrong_digest.encode("ascii")
            + b"\0"
        )
        remove_output()
        subprocess.run(
            ["python3", str(script)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert not output.exists(), (
            "extract_c2.py wrote c2_address.txt even though the SHA-256 verification failed"
        )
    finally:
        cmdline.write_bytes(original_cmdline)
        remove_output()
        if original_output is not None:
            output.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
