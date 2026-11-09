#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import shutil
import socket
import subprocess
import time
import pytest


def weak_hash(data: bytes) -> int:
    """Python implementation of the Rust weak_hash function."""
    hash_val = 0
    for i, b in enumerate(data):
        hash_val = (hash_val + b * (i + 1)) % (2**32)
    return hash_val


def test_open_port_correct():
    """Validates that open_port.txt contains the correct port derived from firewall_rules.json."""
    rules_file = "/home/user/audit/firewall_rules.json"
    port_file = "/home/user/audit/open_port.txt"

    assert os.path.exists(rules_file), f"Missing {rules_file}"
    with open(rules_file, "r") as f:
        try:
            rules = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{rules_file} is not valid JSON")

    expected_port = None
    for policy in rules.get("policies", []):
        if policy.get("service") == "internal_file_server":
            expected_port = policy.get("port")
            break

    assert expected_port is not None, "Could not find 'internal_file_server' policy in firewall_rules.json to derive the expected port."

    assert os.path.exists(port_file), f"Missing {port_file}. The task requires writing the port number to this file."
    with open(port_file, "r") as f:
        actual_port = f.read().strip()

    assert actual_port == str(expected_port), f"Expected port {expected_port} in {port_file}, but found '{actual_port}'."


def test_csp_header_in_server():
    """Validates that the correct Content-Security-Policy header was added to server.rs."""
    server_file = "/home/user/audit/server.rs"
    assert os.path.exists(server_file), f"Missing {server_file}"

    with open(server_file, "r") as f:
        content = f.read()

    expected_header = "Content-Security-Policy: default-src 'self'; script-src 'none';"
    assert expected_header in content, (
        f"The required CSP header '{expected_header}' was not found in {server_file}."
    )


def test_compiled_server_emits_csp_header_with_valid_http_format():
    """Compiles the submitted source and verifies the header is in its actual 200 response."""
    server_file = "/home/user/audit/server.rs"
    binary = "/tmp/audit_server_under_test"
    expected_header = b"Content-Security-Policy: default-src 'self'; script-src 'none';"

    assert os.path.isfile(server_file), f"Missing regular source file {server_file}"
    rustc = shutil.which("rustc")
    assert rustc is not None, "rustc is required to verify the submitted Rust server"

    try:
        compiled = subprocess.run(
            [rustc, server_file, "-o", binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Compilation of server.rs timed out")

    assert compiled.returncode == 0, (
        "server.rs did not compile successfully:\n" + compiled.stderr
    )

    with open("/home/user/audit/firewall_rules.json", "r") as f:
        rules = json.load(f)
    port = next(
        policy["port"] for policy in rules.get("policies", [])
        if policy.get("service") == "internal_file_server"
    )

    proc = subprocess.Popen(
        [binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    response = b""
    try:
        deadline = time.monotonic() + 5
        sock = None
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors="replace")
                pytest.fail(f"Compiled server exited before accepting a request: {stderr}")
            try:
                sock = socket.create_connection(("127.0.0.1", int(port)), timeout=1)
                break
            except OSError:
                time.sleep(0.05)

        assert sock is not None, f"Compiled server did not listen on port {port}"
        with sock:
            sock.settimeout(3)
            sock.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            while True:
                try:
                    chunk = sock.recv(4096)
                except socket.timeout:
                    pytest.fail("Timed out while reading the server response")
                if not chunk:
                    break
                response += chunk
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)

    header_block, separator, body = response.partition(b"\r\n\r\n")
    assert separator == b"\r\n\r\n", (
        "The HTTP response must separate headers from the body with a blank CRLF line"
    )

    header_lines = header_block.split(b"\r\n")
    assert header_lines and header_lines[0] == b"HTTP/1.1 200 OK", (
        f"Expected an HTTP/1.1 200 OK response, got {response!r}"
    )
    assert all(b"\r" not in line and b"\n" not in line for line in header_lines), (
        "Response headers contain malformed line endings"
    )
    assert expected_header in header_lines[1:], (
        "The actual 200 OK response did not contain the required CSP header as an exact header line"
    )


def test_forged_config_collision():
    """Validates the cryptanalysis task by checking the forged file's prefix and hash collision."""
    forged_file = "/home/user/audit/forged_config.txt"
    assert os.path.exists(forged_file), f"Missing {forged_file}. The forged configuration file must be created."

    with open(forged_file, "rb") as f:
        forged_data = f.read()

    expected_prefix = b"role=admin"
    assert forged_data.startswith(expected_prefix), (
        f"The forged config must start with exactly '{expected_prefix.decode()}', "
        f"but it started with '{forged_data[:10]}'."
    )

    target_data = b"role=standard_user"
    target_hash = weak_hash(target_data)
    forged_hash = weak_hash(forged_data)

    assert forged_hash == target_hash, (
        f"Hash collision failed. Expected hash {target_hash} (derived from '{target_data.decode()}'), "
        f"but the forged file produced hash {forged_hash}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
