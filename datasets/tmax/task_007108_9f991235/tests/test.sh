#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import stat
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/analyze_redirects.sh"
OUTPUT_PATH = "/home/user/compromised_sessions.txt"
LOG_PATH = "/home/user/audit_data/access.log"


def compute_expected_lines(path):
    expected_lines = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Parse the log line
            # Format: IP_ADDRESS - - [DATE] "METHOD PATH_WITH_QUERY HTTP_VERSION" STATUS_CODE RESPONSE_SIZE "session_id=TOKEN"
            parts = line.split('"')
            if len(parts) >= 3:
                request_part = parts[1]
                # Extract redirect URL
                redirect_match = re.search(r'redirect=(https?://[^ ]+)', request_part)

                # Extract status code
                post_request_parts = parts[2].strip().split()
                if len(post_request_parts) >= 1:
                    status_code = post_request_parts[0]

                    if redirect_match and status_code == "302":
                        malicious_url = redirect_match.group(1)

                        # Redact IP address
                        ip_match = re.match(r'^(\d+\.\d+\.\d+\.)(\d+)', line)
                        if ip_match:
                            redacted_ip = f"***.***.***.{ip_match.group(2)}"
                            redacted_line = line.replace(ip_match.group(0), redacted_ip, 1)
                        else:
                            redacted_line = line

                        # Redact session_id
                        redacted_line = re.sub(r'session_id=[^\"]+', 'session_id=REDACTED', redacted_line)
                        expected_lines.append(f"[{malicious_url}] {redacted_line}")
    return expected_lines


def test_script_exists_and_executable():
    """Verify that the analysis script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_output_file_exists():
    """Verify that the compromised sessions output file exists."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_output_file_content():
    """Verify that the compromised sessions file contains the correctly extracted and redacted data."""
    assert os.path.isfile(LOG_PATH), f"Source log file {LOG_PATH} is missing."

    # Dynamically compute the expected output from the log file
    expected_lines = compute_expected_lines(LOG_PATH)

    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_script_executes_correctly_on_altered_input():
    """Execute the submitted script against fresh unpredictable log data."""
    original_log = open(LOG_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.exists(OUTPUT_PATH) else None

    nonce1 = secrets.token_hex(8)
    nonce2 = secrets.token_hex(8)
    token1 = secrets.token_hex(12)
    token2 = secrets.token_hex(12)
    last1 = 1 + secrets.randbelow(254)
    last2 = 1 + secrets.randbelow(254)
    url1 = f"http://{nonce1}.example/payload"
    url2 = f"https://{nonce2}.example/collect"

    altered_lines = [
        f'21.22.23.{last1} - - [21/Nov/2023:09:00:00 +0000] "GET /login?redirect={url1} HTTP/1.1" 302 701 "session_id={token1}"',
        '31.32.33.44 - - [21/Nov/2023:09:01:00 +0000] "GET /login?redirect=/account HTTP/1.1" 302 702 "session_id=normal-session"',
        f'41.42.43.45 - - [21/Nov/2023:09:02:00 +0000] "GET /login?redirect=http://blocked.example/path HTTP/1.1" 403 703 "session_id={secrets.token_hex(10)}"',
        f'51.52.53.{last2} - - [21/Nov/2023:09:03:00 +0000] "GET /login?redirect={url2} HTTP/1.1" 302 704 "session_id={token2}"',
        f'61.62.63.64 - - [21/Nov/2023:09:04:00 +0000] "GET /login?redirect=http://not-successful.example/path HTTP/1.1" 200 302 "session_id={secrets.token_hex(10)}"',
        f'71.72.73.74 - - [21/Nov/2023:09:05:00 +0000] "GET /login?redirect=https://rejected.example/path HTTP/1.1" 400 705 "session_id={secrets.token_hex(10)}"',
    ]

    try:
        with open(LOG_PATH, "w") as f:
            f.write("\n".join(altered_lines) + "\n")
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script exited with status {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(OUTPUT_PATH), "Script did not generate compromised_sessions.txt."

        expected_lines = compute_expected_lines(LOG_PATH)
        with open(OUTPUT_PATH, "r") as f:
            actual_lines = [line.strip() for line in f if line.strip()]

        assert actual_lines == expected_lines, (
            "Script output was incorrect for altered input.\n"
            f"Expected: {expected_lines}\nActual:   {actual_lines}"
        )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
