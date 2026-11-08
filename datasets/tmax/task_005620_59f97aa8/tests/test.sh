#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/workspace"
CWE_PATH = os.path.join(WORKSPACE_DIR, "cwe.txt")
ATTACKER_PATH = os.path.join(WORKSPACE_DIR, "attacker.txt")
DETECT_PY_PATH = os.path.join(WORKSPACE_DIR, "detect.py")
ACCESS_LOG_PATH = os.path.join(WORKSPACE_DIR, "access.log")

def test_cwe_file_content():
    assert os.path.isfile(CWE_PATH), f"File {CWE_PATH} does not exist."
    with open(CWE_PATH, "r") as f:
        content = f.read().strip()
    assert content == "CWE-601", f"Expected 'CWE-601' in {CWE_PATH}, but got '{content}'."

def test_attacker_file_content():
    assert os.path.isfile(ATTACKER_PATH), f"File {ATTACKER_PATH} does not exist."
    with open(ATTACKER_PATH, "r") as f:
        content = f.read().strip()
    assert content == "10.10.10.10", f"Expected '10.10.10.10' in {ATTACKER_PATH}, but got '{content}'."

def test_detect_script_exists():
    assert os.path.isfile(DETECT_PY_PATH), f"File {DETECT_PY_PATH} does not exist."

def test_detect_script_output_original_log():
    result = subprocess.run(
        ["python3", DETECT_PY_PATH, ACCESS_LOG_PATH],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"detect.py exited with code {result.returncode}. Error: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    expected_lines = ["10.10.10.10", "192.168.1.51"]

    assert output_lines == expected_lines, f"Expected output {expected_lines}, but got {output_lines}"

def test_detect_script_output_custom_log():
    custom_log_content = """1.1.1.1 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=/dashboard HTTP/1.1" 200 2326
2.2.2.2 - - [10/Oct/2023:13:56:10 -0700] "GET /login?next=http://bad.com HTTP/1.1" 302 2326
3.3.3.3 - - [10/Oct/2023:13:57:36 -0700] "GET /login?next=https://worse.org HTTP/1.1" 302 2326
4.4.4.4 - - [10/Oct/2023:13:58:00 -0700] "POST /login?next=http://evil.com HTTP/1.1" 302 2326
2.2.2.2 - - [10/Oct/2023:13:56:10 -0700] "GET /login?next=http://bad.com HTTP/1.1" 302 2326
5.5.5.5 - - [10/Oct/2023:13:59:00 -0700] "GET /other?next=http://evil.com HTTP/1.1" 200 1234
"""
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp_log:
        tmp_log.write(custom_log_content)
        tmp_log_path = tmp_log.name

    try:
        result = subprocess.run(
            ["python3", DETECT_PY_PATH, tmp_log_path],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"detect.py exited with code {result.returncode} on custom log."

        output_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        expected_lines = ["2.2.2.2", "3.3.3.3"]

        assert output_lines == expected_lines, (
            f"detect.py did not correctly parse the custom log. "
            f"Expected {expected_lines}, but got {output_lines}."
        )
    finally:
        os.remove(tmp_log_path)

def test_detect_script_output_generated_logs():
    rng = random.SystemRandom()

    for _ in range(4):
        prefix = f"{rng.randint(20, 220)}.{rng.randint(1, 250)}.{rng.randint(1, 250)}"
        suffixes = rng.sample(range(100, 200), 9)
        ips = [f"{prefix}.{suffix}" for suffix in suffixes]
        token = secrets.token_hex(12)

        cases = [
            (ips[0], "GET", f"/login?next=http://{token}.example/phish", True),
            (ips[1], "GET", f"/login?source=email&next=https://{token}.invalid/signin", True),
            (ips[2], "GET", "/login?next=/dashboard", False),
            (ips[3], "POST", f"/login?next=http://{token}.example/phish", False),
            (ips[4], "GET", f"/other?next=https://{token}.invalid/", False),
            (ips[5], "GET", f"/login?redirect=http://{token}.example/&next=/home", False),
            (ips[6], "GET", f"/login?next=ftp://{token}.example/file", False),
            (ips[0], "GET", f"/login?next=http://{token}.example/phish", True),
            (ips[7], "GET", f"/login?next=https://{token}.example/landing&source=ad", True),
            (ips[8], "GET", "/login", False),
        ]
        rng.shuffle(cases)

        lines = []
        expected = set()
        for index, (ip, method, target, is_attack) in enumerate(cases):
            status = rng.choice([200, 301, 302, 404])
            lines.append(
                f'{ip} - - [11/Sep/2026:12:{index:02d}:00 +0000] '
                f'"{method} {target} HTTP/1.1" {status} {rng.randint(100, 9999)}'
            )
            if is_attack:
                expected.add(ip)

        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp_log:
            tmp_log.write("\n".join(lines) + "\n")
            tmp_log_path = tmp_log.name

        try:
            result = subprocess.run(
                ["python3", DETECT_PY_PATH, tmp_log_path],
                capture_output=True,
                text=True
            )
            assert result.returncode == 0, (
                f"detect.py exited with code {result.returncode} on a generated log. "
                f"Error: {result.stderr}"
            )
            output_lines = result.stdout.splitlines()
            expected_lines = sorted(expected)
            assert output_lines == expected_lines, (
                f"detect.py did not correctly parse a generated log. "
                f"Expected {expected_lines}, but got {output_lines}."
            )
        finally:
            os.remove(tmp_log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
