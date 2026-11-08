#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import socket
import stat
import subprocess
import time
import uuid

import pytest


def test_server_setup_permissions():
    path = "/home/user/server_setup.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    match = re.search(r'chmod\s+(?:600|u=rw,g=,o=)\s+.*?db_secret\.key', content)
    assert match is not None, "server_setup.sh does not properly set permissions to 600 for db_secret.key"


def test_server_setup_headers():
    path = "/home/user/server_setup.sh"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r'X-Content-Type-Options\\?:\s*nosniff', content, re.IGNORECASE), \
        "server_setup.sh does not include the X-Content-Type-Options: nosniff header."
    assert re.search(r'X-Frame-Options\\?:\s*DENY', content, re.IGNORECASE), \
        "server_setup.sh does not include the X-Frame-Options: DENY header."


def test_server_setup_runtime_behavior():
    path = "/home/user/server_setup.sh"

    # Do not accept a server left running independently of server_setup.sh.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        probe.bind(("127.0.0.1", 8080))
    except OSError:
        pytest.fail("TCP port 8080 was already occupied before server_setup.sh was executed")
    finally:
        probe.close()

    # Use a hostile pre-existing mode so merely overwriting the file cannot pass.
    key_path = "/home/user/www/config/db_secret.key"
    os.makedirs(os.path.dirname(key_path), exist_ok=True)
    with open(key_path, "w") as f:
        f.write("old insecure value\n")
    os.chmod(key_path, 0o666)

    proc = subprocess.Popen(
        [path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    response = b""
    last_error = None
    try:
        deadline = time.time() + 6
        while time.time() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.5) as client:
                    client.settimeout(2)
                    client.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
                    chunks = []
                    while True:
                        try:
                            chunk = client.recv(4096)
                        except socket.timeout:
                            break
                        if not chunk:
                            break
                        chunks.append(chunk)
                    response = b"".join(chunks)
                    break
            except OSError as exc:
                last_error = exc
                if proc.poll() is not None:
                    break
                time.sleep(0.1)

        assert response, f"server_setup.sh did not launch a responding socat HTTP server: {last_error}"

        mode = stat.S_IMODE(os.stat(key_path).st_mode)
        assert mode == 0o600, f"db_secret.key runtime mode is {mode:o}, expected 600"

        text = response.decode("utf-8", errors="replace")
        assert re.search(r'(?im)^X-Content-Type-Options:\s*nosniff\s*\r?$', text), \
            "The actual HTTP response lacks X-Content-Type-Options: nosniff"
        assert re.search(r'(?im)^X-Frame-Options:\s*DENY\s*\r?$', text), \
            "The actual HTTP response lacks X-Frame-Options: DENY"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)


def run_greet(query):
    path = "/home/user/src/cgi-bin/greet.sh"
    env = os.environ.copy()
    env["QUERY_STRING"] = query
    return subprocess.run(
        [path],
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    ).stdout


def test_greet_script_injection():
    path = "/home/user/src/cgi-bin/greet.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "eval " not in content, "greet.sh still contains the unsafe 'eval' command."
    sanitization_found = any(x in content for x in ["tr ", "sed ", "${NAME//", "gsub"])
    assert "echo" in content, "greet.sh must still output the value."

    # Verify that the script really parses and reflects a runtime-derived name.
    benign = "Visitor" + uuid.uuid4().hex
    output = run_greet("name=" + benign)
    assert re.search(r'(?im)^Content-Type:\s*text/html\s*\r?$', output), \
        "greet.sh does not emit its CGI HTML content type"
    assert benign in output, "greet.sh did not output the supplied name parameter"

    # Exercise command substitution with a fresh sentinel rather than trusting text.
    token = uuid.uuid4().hex
    sentinel = "/tmp/greet_injection_" + token
    left = "Left" + uuid.uuid4().hex
    right = "Right" + uuid.uuid4().hex
    if os.path.exists(sentinel):
        os.unlink(sentinel)
    malicious = f"name={left}$(touch {sentinel}){right}"
    attacked_output = run_greet(malicious)
    assert not os.path.exists(sentinel), "greet.sh executed command substitution from name"
    assert left in attacked_output and right in attacked_output, \
        "greet.sh did not parse and output the maliciously shaped name safely"

    # Confirm that dangerous shell metacharacters are removed from reflected output.
    parts = [uuid.uuid4().hex[:8] for _ in range(5)]
    dirty_name = parts[0] + ";" + parts[1] + "|" + parts[2] + "$" + parts[3] + "`" + parts[4]
    sanitized_output = run_greet("name=" + dirty_name)
    for part in parts:
        assert part in sanitized_output, "greet.sh replaced the name with static output"
    for bad in ";|$`":
        assert bad not in sanitized_output, f"greet.sh did not sanitize dangerous character {bad!r}"


def test_audit_report():
    path = "/home/user/audit_report.json"
    assert os.path.isfile(path), f"Audit report {path} does not exist."

    with open(path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    expected = {
      "vulnerabilities_fixed": [
        "Insecure File Permissions",
        "Missing Security Headers",
        "Command Injection"
      ],
      "db_secret_permission": "600",
      "added_headers": ["X-Content-Type-Options", "X-Frame-Options"]
    }

    assert report == expected, f"Audit report content does not match the expected structure. Got: {report}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
