#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import shlex
import subprocess


def get_expected_values():
    ca_path = "/home/user/ca.crt"
    cert_dir = "/home/user/client_certs"
    valid_pairs = []

    for index in range(1, 4):
        cert_path = os.path.join(cert_dir, f"client{index}.crt")
        key_path = os.path.join(cert_dir, f"client{index}.key")
        result = subprocess.run(
            ["openssl", "verify", "-CAfile", ca_path, cert_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            valid_pairs.append((cert_path, key_path))

    assert len(valid_pairs) == 1, "Could not identify exactly one CA-signed client certificate."
    cert_path, key_path = valid_pairs[0]

    result = subprocess.run(
        [
            "curl", "--silent", "--show-error", "--fail",
            "--cacert", ca_path,
            "--cert", cert_path,
            "--key", key_path,
            "https://localhost:8443/payload",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"Could not retrieve payload over verified mTLS: {result.stderr.decode(errors='replace')}"

    try:
        payload = base64.b64decode(result.stdout.strip(), validate=True).decode("utf-8")
    except Exception as exc:
        raise AssertionError(f"Service returned an invalid Base64 payload: {exc}")

    match = re.fullmatch(r"IP:([^;]+);PORT:([^;]+);FLAG:([^;]+)", payload)
    assert match, "Could not parse the decoded service payload."
    return match.group(1), match.group(2), match.group(3)


def count_iptables_commands(content):
    count = 0
    for line in content.splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        lexer.commenters = "#"
        try:
            tokens = list(lexer)
        except ValueError as exc:
            raise AssertionError(f"The block script has invalid shell quoting: {exc}")

        command_start = True
        for token in tokens:
            if token and all(ch in ";&|" for ch in token):
                command_start = True
                continue
            if command_start:
                if token in ("sudo", "command", "env") or ("=" in token and not token.startswith("=")):
                    continue
                if os.path.basename(token) == "iptables":
                    count += 1
                command_start = False
    return count


def test_flag_file_contents():
    _, _, expected_flag = get_expected_values()
    flag_path = "/home/user/flag.txt"

    assert os.path.isfile(flag_path), f"The file {flag_path} does not exist."

    with open(flag_path, "r") as f:
        content = f.read().strip()

    assert content == expected_flag, f"The content of {flag_path} is incorrect. Expected '{expected_flag}', got '{content}'."


def test_block_vuln_script():
    expected_ip, expected_port, _ = get_expected_values()
    script_path = "/home/user/block_vuln.sh"

    assert os.path.isfile(script_path), f"The file {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    pattern = rf"iptables\s+-A\s+OUTPUT\s+-p\s+tcp\s+-d\s+{re.escape(expected_ip)}\s+--dport\s+{re.escape(expected_port)}\s+-j\s+DROP"

    assert re.search(pattern, content), (
        f"The script {script_path} does not contain the correct iptables command. "
        f"Expected it to block outbound tcp traffic to IP {expected_ip} on port {expected_port}."
    )
    assert count_iptables_commands(content) == 1, (
        f"The script {script_path} must contain exactly one iptables command."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
