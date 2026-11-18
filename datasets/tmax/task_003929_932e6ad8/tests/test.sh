#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import stat
import subprocess

INCIDENT_PATH = "/home/user/incident_log.txt"
SOURCE_PATH = "/home/user/analyzer.rs"
BINARY_PATH = "/home/user/analyzer"
MITIGATION_PATH = "/home/user/mitigation.sh"
CSP_PATH = "/home/user/csp_header.txt"
REBUILT_PATH = "/tmp/analyzer_from_source"

CANONICAL_REQUEST = """GET /api/v1/status HTTP/1.1
Host: internal.corp.local
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Cookie: session_id=987654321; auth_token=f0VMRsYzZBY=; pref=dark
Accept: application/json
Connection: close
"""


def write_request(payload, cookie_prefix="session_id=987654321", cookie_suffix="pref=dark"):
    token = base64.b64encode(payload).decode("ascii")
    request = (
        "GET /api/v1/status HTTP/1.1\r\n"
        "Host: internal.corp.local\r\n"
        "User-Agent: verifier\r\n"
        f"Cookie: {cookie_prefix}; auth_token={token}; {cookie_suffix}\r\n"
        "Accept: application/json\r\n"
        "Connection: close\r\n\r\n"
    )
    with open(INCIDENT_PATH, "w", newline="") as f:
        f.write(request)


def remove_outputs():
    for path in (MITIGATION_PATH, CSP_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_program(path):
    return subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )


def assert_generated(ip):
    assert os.path.isfile(MITIGATION_PATH), "Analyzer did not create mitigation.sh"
    st = os.stat(MITIGATION_PATH)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), "mitigation.sh is not executable"
    with open(MITIGATION_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]
    assert actual_lines == [
        "#!/bin/bash",
        f"iptables -A INPUT -s {ip} -j DROP",
    ]

    assert os.path.isfile(CSP_PATH), "Analyzer did not create csp_header.txt"
    with open(CSP_PATH, "r") as f:
        csp = f.read().strip()
    assert csp == "Content-Security-Policy: default-src 'none';"


def exercise_success(path, octets, prefix, suffix):
    ip = ".".join(str(value) for value in octets)
    write_request(b"\x7fELF" + bytes(octets), prefix, suffix)
    remove_outputs()
    result = run_program(path)
    assert result.returncode == 0, f"{path} failed on valid payload: {result.stderr}"
    assert_generated(ip)


def exercise_invalid_magic(path):
    write_request(b"BAD!" + secrets.token_bytes(4), "a=1", "b=2")
    remove_outputs()
    result = run_program(path)
    assert result.returncode != 0, f"{path} accepted a payload without ELF magic"


def random_ip_octets():
    return [secrets.randbelow(223) + 1, secrets.randbelow(256), secrets.randbelow(256), secrets.randbelow(254) + 1]


def test_00_analyzer_artifacts_and_behavior():
    assert os.path.exists(SOURCE_PATH), f"File {SOURCE_PATH} is missing."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."
    assert os.path.exists(BINARY_PATH), f"File {BINARY_PATH} is missing."
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable."

    compiled = subprocess.run(
        ["rustc", SOURCE_PATH, "-o", REBUILT_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compiled.returncode == 0, f"analyzer.rs does not compile with rustc: {compiled.stderr}"

    exercise_success(REBUILT_PATH, random_ip_octets(), "theme=light", "session_id=source-test")
    exercise_invalid_magic(REBUILT_PATH)
    exercise_success(BINARY_PATH, random_ip_octets(), "not_auth_token=AAAA", "pref=binary-test")
    exercise_invalid_magic(BINARY_PATH)

    with open(INCIDENT_PATH, "w") as f:
        f.write(CANONICAL_REQUEST)
    remove_outputs()
    result = run_program(BINARY_PATH)
    assert result.returncode == 0, f"Submitted analyzer failed on the captured request: {result.stderr}"


def test_mitigation_script():
    script_path = "/home/user/mitigation.sh"

    assert os.path.exists(script_path), f"File {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    # Check if executable
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), f"File {script_path} is not executable."

    with open(script_path, 'r') as f:
        content = f.read().strip()

    expected_lines = [
        "#!/bin/bash",
        "iptables -A INPUT -s 198.51.100.22 -j DROP"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, f"Content of {script_path} does not match expected output."


def test_csp_header():
    csp_path = "/home/user/csp_header.txt"

    assert os.path.exists(csp_path), f"File {csp_path} is missing."
    assert os.path.isfile(csp_path), f"{csp_path} is not a file."

    with open(csp_path, 'r') as f:
        content = f.read().strip()

    expected_content = "Content-Security-Policy: default-src 'none';"

    assert content == expected_content, f"Content of {csp_path} does not match expected output. Got: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
