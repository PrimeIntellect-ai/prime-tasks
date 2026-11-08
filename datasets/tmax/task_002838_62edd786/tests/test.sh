#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import random
import re
import secrets
import socket
import stat
import time

import pytest
import requests


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def socket_owners(port):
    inodes = listening_socket_inodes(port)
    owners = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        fd_dir = f"/proc/{pid}/fd"
        owns_socket = False
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owns_socket = True
                    break
            if not owns_socket:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = " ".join(x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x)
            exe = os.path.realpath(f"/proc/{pid}/exe")
            cwd = os.path.realpath(f"/proc/{pid}/cwd")
            owners.append({"pid": pid, "cmdline": cmdline, "exe": exe, "cwd": cwd})
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return owners


def resolves_c2_script(owner):
    if not os.path.basename(owner["exe"]).startswith("python"):
        return False
    for token in owner["cmdline"].split():
        if token.endswith("c2_server.py"):
            path = token if os.path.isabs(token) else os.path.join(owner["cwd"], token)
            if os.path.realpath(path) == "/app/c2_server.py":
                return True
    return False


def nginx_uses_required_config(owner):
    cmdline = owner["cmdline"]
    if "/app/nginx.conf" in cmdline:
        return True
    match = re.search(r"(?:^|\s)-c\s+([^\s]+)", cmdline)
    if not match:
        return False
    config = match.group(1)
    if os.path.isabs(config):
        return os.path.realpath(config) == "/app/nginx.conf"
    prefix_match = re.search(r"(?:^|\s)-p\s+([^\s]+)", cmdline)
    base = prefix_match.group(1) if prefix_match else owner["cwd"]
    return os.path.realpath(os.path.join(base, config)) == "/app/nginx.conf"


def post_json(url, payload):
    try:
        return requests.post(url, json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to {url} failed: {exc}")


def test_required_artifacts_and_listeners():
    script = "/app/c2_server.py"
    assert os.path.isfile(script), f"{script} is missing or is not a regular file"
    assert stat.S_ISREG(os.stat(script).st_mode), f"{script} is not a regular file"
    with open(script, "r", encoding="utf-8") as f:
        ast.parse(f.read(), filename=script)

    config = "/app/nginx.conf"
    assert os.path.isfile(config), f"{config} is missing"
    with open(config, "r", encoding="utf-8") as f:
        clean_config = "\n".join(line.split("#", 1)[0] for line in f)
    proxy_targets = [value.strip() for value in re.findall(r"\bproxy_pass\s+([^;]+);", clean_config)]
    assert proxy_targets, "nginx.conf has no active proxy_pass directive"
    assert all(target == "http://127.0.0.1:9000" for target in proxy_targets), \
        f"nginx.conf contains an incorrect proxy_pass target: {proxy_targets}"

    nginx_owners = socket_owners(8000)
    expected_nginx = os.path.realpath("/usr/sbin/nginx")
    assert nginx_owners, "No process owns the listening socket on port 8000"
    assert all(owner["exe"] == expected_nginx for owner in nginx_owners), \
        f"Port 8000 is not owned exclusively by the installed Nginx: {nginx_owners}"
    assert any(nginx_uses_required_config(owner) for owner in nginx_owners), \
        f"The Nginx instance on port 8000 was not started with /app/nginx.conf: {nginx_owners}"

    for port in (9000, 9001):
        owners = socket_owners(port)
        assert owners, f"No process owns the listening socket on port {port}"
        assert all(resolves_c2_script(owner) for owner in owners), \
            f"Port {port} is not owned by Python executing /app/c2_server.py: {owners}"


def test_nginx_proxy_analyze_payload():
    """Test the HTTP REST API /analyze_payload endpoint via Nginx port 8000."""
    url = "http://127.0.0.1:8000/analyze_payload"

    payload_vuln = {"filename": "../../../etc/passwd", "content": "test"}
    try:
        r_vuln = requests.post(url, json=payload_vuln, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8000: {e}")

    assert r_vuln.status_code == 200, f"Expected 200 OK for /analyze_payload, got {r_vuln.status_code}. Response: {r_vuln.text}"
    try:
        data_vuln = r_vuln.json()
    except ValueError:
        pytest.fail(f"Response from /analyze_payload is not valid JSON: {r_vuln.text}")

    assert data_vuln.get("cwe") == "CWE-22" and data_vuln.get("status") == "vulnerable", \
        f"Expected CWE-22 and vulnerable status, got {data_vuln}"

    payload_safe = {"filename": "image.png", "content": "test"}
    r_safe = requests.post(url, json=payload_safe, timeout=2)
    assert r_safe.status_code == 200, f"Expected 200 OK for safe payload, got {r_safe.status_code}"
    data_safe = r_safe.json()
    assert data_safe.get("status") == "safe", f"Expected safe status, got {data_safe}"


def test_nginx_proxy_verify_integrity():
    """Test the HTTP REST API /verify_integrity endpoint via Nginx port 8000."""
    url = "http://127.0.0.1:8000/verify_integrity"
    test_file = "/app/test_file.txt"

    assert os.path.exists(test_file), f"Test file {test_file} is missing"
    with open(test_file, "rb") as f:
        file_hash = hashlib.sha256(f.read()).hexdigest()

    payload_valid = {"filepath": test_file, "expected_sha256": file_hash}
    r_valid = requests.post(url, json=payload_valid, timeout=2)
    assert r_valid.status_code == 200, f"Expected 200 OK for /verify_integrity, got {r_valid.status_code}"
    assert r_valid.json().get("verified") is True, f"Expected verified: true, got {r_valid.json()}"

    payload_invalid = {"filepath": test_file, "expected_sha256": "0000000000000000000000000000000000000000000000000000000000000000"}
    r_invalid = requests.post(url, json=payload_invalid, timeout=2)
    assert r_invalid.status_code == 200, f"Expected 200 OK for invalid hash, got {r_invalid.status_code}"
    assert r_invalid.json().get("verified") is False, f"Expected verified: false, got {r_invalid.json()}"

    payload_404 = {"filepath": "/app/does_not_exist_file.txt", "expected_sha256": file_hash}
    r_404 = requests.post(url, json=payload_404, timeout=2)
    assert r_404.status_code == 404, f"Expected 404 for missing file, got {r_404.status_code}"


def test_tcp_log_parsing():
    """Test the Raw TCP Log Receiver on port 9001."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(("127.0.0.1", 9001))
    except Exception as e:
        pytest.fail(f"Could not connect to TCP port 9001: {e}")

    log_line = "[2024-01-01T00:00:00Z] 10.0.0.5 EXFILTRATE /etc/shadow\n"
    s.sendall(log_line.encode("utf-8"))
    s.close()
    time.sleep(1.0)

    log_file = "/app/parsed_logs.json"
    assert os.path.isfile(log_file), f"{log_file} does not exist. TCP server may not be writing logs correctly."

    found = False
    with open(log_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if (obj.get("timestamp") == "2024-01-01T00:00:00Z" and
                    obj.get("ip") == "10.0.0.5" and
                    obj.get("action") == "EXFILTRATE" and
                    obj.get("target") == "/etc/shadow"):
                    found = True
                    break
            except json.JSONDecodeError:
                pass

    assert found, f"Did not find the expected parsed JSON log object in {log_file}"


def test_randomized_payload_analysis_and_integrity():
    analyze_url = "http://127.0.0.1:8000/analyze_payload"
    token = secrets.token_hex(10)
    cases = [
        (f"uploads/{token}/image..png", False),
        (f"{token}-plain.txt", False),
        (f"uploads/../{token}/secret.txt", True),
        (f"uploads\\..\\{token}\\secret.txt", True),
    ]
    random.shuffle(cases)
    for filename, vulnerable in cases:
        response = post_json(analyze_url, {"filename": filename, "content": secrets.token_hex(13)})
        assert response.status_code == 200
        data = response.json()
        if vulnerable:
            assert data.get("cwe") == "CWE-22" and data.get("status") == "vulnerable", \
                f"Traversal filename {filename!r} was not identified: {data}"
        else:
            assert data.get("status") == "safe", f"Safe filename {filename!r} was not marked safe: {data}"

    integrity_url = "http://127.0.0.1:8000/verify_integrity"
    path = f"/app/verifier_{secrets.token_hex(10)}.bin"
    original = os.urandom(127 + random.randrange(128))
    try:
        with open(path, "wb") as f:
            f.write(original)
        original_hash = hashlib.sha256(original).hexdigest()
        response = post_json(integrity_url, {"filepath": path, "expected_sha256": original_hash})
        assert response.status_code == 200 and response.json().get("verified") is True

        changed = original + os.urandom(17)
        with open(path, "wb") as f:
            f.write(changed)
        response = post_json(integrity_url, {"filepath": path, "expected_sha256": original_hash})
        assert response.status_code == 200 and response.json().get("verified") is False

        changed_hash = hashlib.sha256(changed).hexdigest()
        response = post_json(integrity_url, {"filepath": path, "expected_sha256": changed_hash})
        assert response.status_code == 200 and response.json().get("verified") is True
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    missing = f"/app/missing_{secrets.token_hex(16)}"
    response = post_json(integrity_url, {"filepath": missing, "expected_sha256": secrets.token_hex(32)})
    assert response.status_code == 404


def test_randomized_tcp_log_parsing():
    marker = secrets.token_hex(8)
    records = []
    lines = []
    for index in range(3):
        record = {
            "timestamp": f"2031-07-{10 + index:02d}T12:34:{20 + index:02d}Z",
            "ip": f"172.29.{random.randrange(1, 250)}.{random.randrange(1, 250)}",
            "action": f"ACTION_{marker}_{index}",
            "target": f"/tmp/{marker}/target_{index}.dat",
        }
        records.append(record)
        lines.append(f"[{record['timestamp']}] {record['ip']} {record['action']} {record['target']}\n")

    with socket.create_connection(("127.0.0.1", 9001), timeout=2) as sock:
        sock.sendall("".join(lines).encode("utf-8"))

    deadline = time.time() + 3
    found = set()
    parse_error = None
    while time.time() < deadline:
        found.clear()
        parse_error = None
        try:
            with open("/app/parsed_logs.json", "r", encoding="utf-8") as f:
                for line_number, line in enumerate(f, 1):
                    if not line.strip():
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError as exc:
                        parse_error = f"Invalid JSONL at line {line_number}: {exc}"
                        break
                    for index, expected in enumerate(records):
                        if all(obj.get(key) == value for key, value in expected.items()):
                            found.add(index)
        except FileNotFoundError:
            pass
        if parse_error is None and len(found) == len(records):
            break
        time.sleep(0.1)

    assert parse_error is None, parse_error
    assert len(found) == len(records), f"Only found randomized log records {sorted(found)} in parsed_logs.json"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
