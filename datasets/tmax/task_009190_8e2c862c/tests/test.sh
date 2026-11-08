#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

NEW_KEY = "NEW_SECURE_KEY_2024"
OLD_KEY = "LEGACY_KEY_884"

ORIGINAL_TRAFFIC = [
    "192.168.1.10 session=role=user:3e2a2324061c1c1e2d",
    "10.0.0.55 session=role=user:3e2a2324061c1c1e2d",
    "172.16.0.4 session=role=admin:3e2a2324061c1c1e2d",
    "192.168.1.101 session=role=user:3e2a2324061c1c1e2d",
    "203.0.113.8 session=role=admin:000000000000000000",
    "198.51.100.2 session=role=user:abcdef1234567890",
]


def compute_hash(data: str, key: str) -> str:
    """Recompute the XOR hash as done in the C++ service."""
    out = ""
    for i in range(len(data)):
        c = ord(data[i]) ^ ord(key[i % len(key)])
        out += f"{c:02x}"
    return out


def make_request(data: str, hash_value: str) -> str:
    return (
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        f"Cookie: session={data}:{hash_value}\r\n"
        "\r\n"
    )


def run_server(binary: str, payload: str):
    return subprocess.run(
        [binary], input=payload, text=True, capture_output=True, timeout=5
    )


def test_auth_server_cpp_updated():
    filepath = "/home/user/auth_server.cpp"
    assert os.path.isfile(filepath), f"Missing required file: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    assert "NEW_SECURE_KEY_2024" in content, "The file auth_server.cpp does not contain the new secure key."
    assert "LEGACY_KEY_884" not in content, "The file auth_server.cpp still contains the legacy key."

    result = subprocess.run(
        ["g++", filepath, "-o", "/tmp/rebuilt_auth_server"],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Updated C++ source does not compile with g++: {result.stderr}"


def test_auth_server_compiled():
    filepath = "/home/user/auth_server"
    assert os.path.isfile(filepath), f"Compiled binary missing: {filepath}"
    assert os.access(filepath, os.X_OK), f"File is not executable: {filepath}"

    with open(filepath, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", "auth_server must be a compiled ELF executable, not a script."


def test_admin_payload_format_and_content():
    filepath = "/home/user/admin_payload.http"
    assert os.path.isfile(filepath), f"Missing required file: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    match = re.search(r"Cookie:\s*session=([^:\r\n]+):([a-fA-F0-9]+)", content)
    assert match is not None, "admin_payload.http does not contain a correctly formatted Cookie header."

    data, hash_val = match.groups()
    assert data == "role=admin", f"Expected data to be 'role=admin', got '{data}'"

    expected_hash = compute_hash("role=admin", NEW_KEY)
    assert hash_val.lower() == expected_hash.lower(), f"Expected hash {expected_hash}, got {hash_val}"


def test_auth_server_execution_with_payload():
    binary = "/home/user/auth_server"
    payload = "/home/user/admin_payload.http"

    assert os.path.isfile(binary), f"Missing binary: {binary}"
    assert os.path.isfile(payload), f"Missing payload: {payload}"

    with open(payload, "r") as f:
        payload_data = f.read()

    result = run_server(binary, payload_data)
    assert "Access Granted: Admin" in result.stdout, (
        f"Expected 'Access Granted: Admin' in output, got: {result.stdout.strip()}"
    )


def test_compiled_server_matches_updated_source_and_protocol():
    source = "/home/user/auth_server.cpp"
    submitted = "/home/user/auth_server"
    rebuilt = "/tmp/rebuilt_auth_server_behavior"

    compile_result = subprocess.run(
        ["g++", source, "-o", rebuilt], text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, f"Updated source failed to compile: {compile_result.stderr}"

    cases = []
    cases.append((make_request("role=admin", compute_hash("role=admin", NEW_KEY)), 0, "Access Granted: Admin\n"))

    for data in ["role=user", "guest", "account=test42", "z9"]:
        cases.append((make_request(data, compute_hash(data, NEW_KEY)), 0, "Access Granted: User\n"))

    cases.extend([
        (make_request("role=admin", compute_hash("role=admin", OLD_KEY)), 1, "Access Denied: Invalid Signature\n"),
        (make_request("role=user", "00" * len("role=user")), 1, "Access Denied: Invalid Signature\n"),
        ("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n", 1, "Access Denied: No Cookie\n"),
        ("GET / HTTP/1.1\r\nCookie: session=role=admin\r\n\r\n", 1, "Access Denied: Missing Signature\n"),
    ])

    for payload, expected_code, expected_stdout in cases:
        actual = run_server(submitted, payload)
        reference = run_server(rebuilt, payload)

        assert (reference.returncode, reference.stdout, reference.stderr) == (
            expected_code,
            expected_stdout,
            "",
        ), "The updated source does not implement the required authentication behavior."
        assert (actual.returncode, actual.stdout, actual.stderr) == (
            reference.returncode,
            reference.stdout,
            reference.stderr,
        ), "auth_server does not behave like the updated C++ source compiled with g++."


def test_firewall_rules_generated_correctly():
    filepath = "/home/user/firewall_rules.sh"
    assert os.path.isfile(filepath), f"Missing required file: {filepath}"

    with open("/home/user/traffic.log", "r") as f:
        traffic_lines = [line.strip() for line in f if line.strip()]
    assert traffic_lines == ORIGINAL_TRAFFIC, "The provided historical traffic.log was modified."

    malicious_ips = []
    for line in ORIGINAL_TRAFFIC:
        ip, cookie = line.split(None, 1)
        valid = False
        if cookie.startswith("session="):
            session_value = cookie[len("session="):]
            if ":" in session_value:
                data, supplied_hash = session_value.split(":", 1)
                valid = supplied_hash == compute_hash(data, OLD_KEY)
        if not valid:
            malicious_ips.append(ip)

    expected_ips = sorted(malicious_ips)
    expected_lines = [f"iptables -A INPUT -s {ip} -j DROP" for ip in expected_ips]

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} iptables rules, got {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Rule {i+1} mismatch. Expected '{expected}', got '{actual}'"

    with open(filepath, "r") as f:
        raw_lines = f.read().splitlines()
    assert raw_lines == expected_lines, "firewall_rules.sh must contain exactly one sorted rule line per malicious IP."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
