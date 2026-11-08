#!/bin/bash
set -e
mkdir -p /logs/verifier

run_checks() (
    set -e

    server_pid=""
    exploit_bin=""
    cleanup() {
        if [ -n "$server_pid" ]; then
            kill "$server_pid" 2>/dev/null || true
            wait "$server_pid" 2>/dev/null || true
        fi
        if [ -n "$exploit_bin" ]; then
            rm -f "$exploit_bin"
        fi
    }
    trap cleanup EXIT

    # Compile the submitted C++ source rather than trusting a placeholder file.
    test -f /home/user/exploit.cpp
    exploit_bin=$(mktemp /tmp/exploit-verifier.XXXXXX)
    g++ -std=c++17 /home/user/exploit.cpp -o "$exploit_bin"
    chmod 0755 "$exploit_bin"

    # Reset the service and all writable state. The exploit runs as nobody while
    # the real service runs as root, so only a request through the vulnerable
    # service can create /home/user/flag.txt.
    pkill -x vuln_server 2>/dev/null || true
    sleep 1
    rm -f /home/user/flag.txt
    rm -rf /home/user/uploads
    mkdir -p /home/user/uploads
    chown root:root /home/user /home/user/uploads
    chmod 0755 /home/user /home/user/uploads

    test -x /home/user/vuln_server
    /home/user/vuln_server >/tmp/vuln-server-verifier.log 2>&1 &
    server_pid=$!
    sleep 1
    kill -0 "$server_pid"

    # Re-execute the submitted exploit without permission to write directly to
    # /home/user. Its result must therefore come from the root-owned service.
    timeout 15s runuser -u nobody -- "$exploit_bin" >/tmp/exploit-verifier.log 2>&1 || true
    sleep 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_flag_txt_exists_and_content():
    """Check if /home/user/flag.txt exists and contains exactly 'PWNED'."""
    path = "/home/user/flag.txt"
    assert os.path.exists(path), f"File {path} does not exist. The exploit may have failed or not run."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "PWNED", f"Content of {path} is '{content}', expected 'PWNED'."
    assert os.stat(path).st_uid == 0, "flag.txt was not created by the root-owned service."

def test_report_txt_exists_and_content():
    """Check if /home/user/report.txt exists and contains the correct answers."""
    path = "/home/user/report.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) >= 3, f"Report file must contain at least 3 lines, found {len(lines)}."

    # Line 1: Port
    assert lines[0] == "9000", f"Line 1 of report should be '9000', found '{lines[0]}'."

    # Line 2: Function name
    valid_funcs = ["process_upload", "process_upload(int)"]
    assert lines[1] in valid_funcs, f"Line 2 of report should be one of {valid_funcs}, found '{lines[1]}'."

    # Line 3: CWE
    valid_cwes = ["CWE-22", "CWE-022"]
    assert lines[2].upper() in valid_cwes, f"Line 3 of report should be 'CWE-22', found '{lines[2]}'."

def test_exploit_cpp_exists():
    """Check if the exploit source file was created."""
    path = "/home/user/exploit.cpp"
    assert os.path.exists(path), f"File {path} does not exist. The exploit source code is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
