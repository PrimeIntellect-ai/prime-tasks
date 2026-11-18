#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import urllib.request
import urllib.error

def test_requirements_txt():
    req_path = "/home/user/workspace/requirements.txt"
    assert os.path.isfile(req_path), "requirements.txt does not exist."
    with open(req_path, "r") as f:
        content = f.read().lower()
        assert "flask" in content, "Flask is not in requirements.txt."

def test_waf_c_patched():
    waf_path = "/home/user/workspace/waf.c"
    assert os.path.isfile(waf_path), "waf.c does not exist."
    with open(waf_path, "r") as f:
        content = f.read()
        assert "<script>" in content, "waf.c does not contain the patched logic."

def test_libwaf_so():
    lib_path = "/home/user/workspace/libwaf.so"
    assert os.path.isfile(lib_path), "libwaf.so does not exist."
    # Check if it's an ELF file
    with open(lib_path, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", "libwaf.so is not a valid ELF file."

def test_server_pid_and_running():
    pid_path = "/home/user/workspace/server.pid"
    assert os.path.isfile(pid_path), "server.pid does not exist."
    with open(pid_path, "r") as f:
        pid_str = f.read().strip()
        assert pid_str.isdigit(), "server.pid does not contain a valid PID."
        pid = int(pid_str)
        # Check if process exists
        assert os.path.isdir(f"/proc/{pid}"), f"Process with PID {pid} is not running."

def test_server_endpoints_and_rate_limiting():
    url = "http://127.0.0.1:8080/submit"

    # Wait a bit to ensure server is fully up and rate limit window is clear
    time.sleep(1)

    def make_request(payload):
        req = urllib.request.Request(url, data=payload.encode('utf-8'), method='POST')
        try:
            with urllib.request.urlopen(req) as response:
                return response.status, response.read().decode('utf-8')
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode('utf-8')
        except urllib.error.URLError:
            return None, None

    # Request 1 (Normal)
    status1, body1 = make_request("hello")
    assert status1 == 200, f"Expected 200 OK for normal request, got {status1}"
    assert "Success" in body1, "Expected 'Success' in response body."

    # Request 2 (Malicious 1)
    status2, _ = make_request("DROP TABLE users")
    assert status2 == 403, f"Expected 403 Forbidden for DROP TABLE payload, got {status2}"

    # Request 3 (Malicious 2 - patched)
    status3, _ = make_request("<script>alert(1)</script>")
    assert status3 == 403, f"Expected 403 Forbidden for <script> payload, got {status3}"

    # Request 4 (Rate limit trigger - 4th request in <10s)
    status4, _ = make_request("test")
    assert status4 == 429, f"Expected 429 Too Many Requests for 4th request, got {status4}"

def test_waf_log():
    log_path = "/home/user/workspace/waf.log"
    assert os.path.isfile(log_path), "waf.log does not exist."
    with open(log_path, "r") as f:
        content = f.read()
        assert "[127.0.0.1] REJECTED: DROP TABLE users" in content, "Missing or incorrect log entry for DROP TABLE."
        assert "[127.0.0.1] REJECTED: <script>alert(1)</script>" in content, "Missing or incorrect log entry for <script>."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
