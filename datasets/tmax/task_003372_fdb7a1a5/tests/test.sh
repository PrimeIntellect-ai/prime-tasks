#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import base64
import socket

ELF_PATH = "/home/user/suspicious.elf"
LOG_PATH = "/home/user/access.log"
OUT_PATH = "/home/user/compromised_ips.txt"

EXPECTED_REGEX = b"^/api/v2/update\\?token=[a-f0-9]{8}"
EXPECTED_ELF = (
    b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    + b"\x00" * 1000
    + b"C2_BEACON: "
    + base64.b64encode(EXPECTED_REGEX)
    + b"\x00"
    + b"\x00" * 100
)
EXPECTED_LOG = """192.168.1.10 - - [10/Oct/2023:13:55:36 -0000] \"GET /index.html HTTP/1.1\" 200 1024
10.0.5.55 - - [10/Oct/2023:13:56:00 -0000] \"GET /api/v2/update?token=deadbeef HTTP/1.1\" 200 452
172.16.0.2 - - [10/Oct/2023:13:57:00 -0000] \"GET /api/v2/update?token=123 HTTP/1.1\" 404 120
10.0.5.55 - - [10/Oct/2023:13:58:00 -0000] \"POST /api/v2/update?token=a1b2c3d4 HTTP/1.1\" 200 90
192.168.1.100 - - [10/Oct/2023:13:59:00 -0000] \"GET /api/v2/update?token=00000000 HTTP/1.1\" 200 12
203.0.113.1 - - [10/Oct/2023:14:00:00 -0000] \"GET /api/v2/update?token=invalid1 HTTP/1.1\" 400 50
"""

def test_compromised_ips_file_exists():
    assert os.path.isfile(OUT_PATH), f"The output file {OUT_PATH} does not exist. Did you create it?"

def test_compromised_ips_content():
    assert os.path.isfile(ELF_PATH), f"Original file {ELF_PATH} is missing."
    assert os.path.isfile(LOG_PATH), f"Original file {LOG_PATH} is missing."

    with open(ELF_PATH, "rb") as f:
        elf_data = f.read()
    with open(LOG_PATH, "rb") as f:
        log_data = f.read()

    assert elf_data == EXPECTED_ELF, f"Original input file {ELF_PATH} was modified."
    assert log_data == EXPECTED_LOG.encode("utf-8"), f"Original input file {LOG_PATH} was modified."

    # 1. Extract and decode the regex from the binary
    match = re.search(rb"C2_BEACON:\s*([A-Za-z0-9+/=]+)", elf_data)
    assert match is not None, "Could not find C2_BEACON string in the binary."

    b64_string = match.group(1)
    regex_pattern = base64.b64decode(b64_string).decode("utf-8")

    # Compile the regex
    malicious_re = re.compile(regex_pattern)

    # 2. Parse the access log and find matching IPs
    compromised_ips = set()
    for line in log_data.decode("utf-8").splitlines():
        # Standard combined log format: IP is the first token.
        parts = line.split(maxsplit=1)
        if not parts:
            continue
        ip = parts[0]

        # Extract request URI
        req_match = re.search(r'"(?:GET|POST|PUT|DELETE|HEAD|OPTIONS) ([^"]+) HTTP', line)
        if req_match:
            request_uri = req_match.group(1)
            if malicious_re.search(request_uri):
                compromised_ips.add(ip)

    # 3. Sort IPs numerically
    def ip_sort_key(ip_str):
        try:
            return socket.inet_aton(ip_str)
        except socket.error:
            return b"\x00\x00\x00\x00"

    expected_ips = sorted(list(compromised_ips), key=ip_sort_key)
    expected_content = "\n".join(expected_ips) + "\n"

    # 4. Read the student's output file
    with open(OUT_PATH, "r") as f:
        actual_content = f.read()

    # Normalize newlines for comparison
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {OUT_PATH} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
