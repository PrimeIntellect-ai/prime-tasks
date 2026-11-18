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
import importlib.util
import json
import os
import re
import signal
import subprocess
import time
import uuid

import pytest
import requests

SERVICE_DIR = "/app/vendored_sso_v1.2"
APP_PATH = os.path.join(SERVICE_DIR, "app.py")
RUN_PATH = os.path.join(SERVICE_DIR, "run.sh")
RUNNERS = []


def test_service_redirects():
    base_url = "http://127.0.0.1:8080/login"

    try:
        # Test 1: Valid relative redirect
        r1 = requests.get(base_url, params={"next": "/profile"}, allow_redirects=False, timeout=2)
        assert r1.status_code == 302, f"Expected 302 for relative path, got {r1.status_code}"
        assert r1.headers.get("Location") == "/profile", f"Expected Location: /profile, got {r1.headers.get('Location')}"

        # Test 2: Absolute URL redirect (http)
        r2 = requests.get(base_url, params={"next": "http://evil.com"}, allow_redirects=False, timeout=2)
        assert r2.status_code == 302, f"Expected 302 for absolute URL, got {r2.status_code}"
        assert r2.headers.get("Location") == "/dashboard", f"Expected Location: /dashboard for absolute URL, got {r2.headers.get('Location')}"

        # Test 3: Protocol-relative redirect
        r3 = requests.get(base_url, params={"next": "//evil.com"}, allow_redirects=False, timeout=2)
        assert r3.status_code == 302, f"Expected 302 for protocol-relative URL, got {r3.status_code}"
        assert r3.headers.get("Location") == "/dashboard", f"Expected Location: /dashboard for protocol-relative URL, got {r3.headers.get('Location')}"

        # Test 4: Missing next parameter
        r4 = requests.get(base_url, allow_redirects=False, timeout=2)
        assert r4.status_code == 302, f"Expected 302 for missing next param, got {r4.status_code}"
        assert r4.headers.get("Location") == "/dashboard", f"Expected Location: /dashboard for missing next param, got {r4.headers.get('Location')}"

    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the service at 127.0.0.1:8080. Ensure it is running.")


def listener_records(port):
    records = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            address, port_hex = fields[1].rsplit(":", 1)
            if int(port_hex, 16) == port:
                records.append((address, fields[9]))
    return records


def pids_for_inodes(inodes):
    found = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        found.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return found


def stop_port(port):
    records = listener_records(port)
    pids = pids_for_inodes([inode for _, inode in records])
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while listener_records(port) and time.time() < deadline:
        time.sleep(0.05)
    if listener_records(port):
        remaining = pids_for_inodes([inode for _, inode in listener_records(port)])
        for pid in remaining:
            os.kill(pid, signal.SIGKILL)
        deadline = time.time() + 2
        while listener_records(port) and time.time() < deadline:
            time.sleep(0.05)
    assert not listener_records(port), "Could not clear the existing listener on port 8080"


def assert_redirect(client, next_value, expected):
    if next_value is None:
        response = client.get("/login")
    else:
        response = client.get("/login", query_string={"next": next_value})
    assert response.status_code == 302
    assert response.headers.get("Location") == expected


def test_repaired_artifacts_and_startup_script():
    assert os.path.isfile(APP_PATH), f"Application file not found at {APP_PATH}"
    assert os.path.isfile(RUN_PATH), f"Startup script not found at {RUN_PATH}"
    assert os.access(RUN_PATH, os.X_OK), f"Startup script is not executable: {RUN_PATH}"

    # Exercise app.py directly with unpredictable values so fixed-value handlers
    # cannot stand in for the required single-slash-relative-path rule.
    spec = importlib.util.spec_from_file_location("submitted_sso_app", APP_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "app.py does not expose the Flask application"
    client = module.app.test_client()

    token = uuid.uuid4().hex
    valid_paths = [f"/{token}", f"/account/{token}", "/"]
    invalid_values = [
        token,
        f"http://{token}.invalid/path",
        f"https://{token}.invalid/path",
        f"//{token}.invalid/path",
        "",
    ]
    for value in valid_paths:
        assert_redirect(client, value, value)
    for value in invalid_values:
        assert_redirect(client, value, "/dashboard")
    assert_redirect(client, None, "/dashboard")

    # Remove the pre-existing service and launch the submitted run.sh with no
    # helpful APP_PORT value. This proves the repaired startup artifact itself
    # starts app.py on the required address and port.
    stop_port(8080)
    env = os.environ.copy()
    env.pop("APP_PORT", None)
    runner = subprocess.Popen(
        [RUN_PATH],
        cwd=SERVICE_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    RUNNERS.append(runner)

    base_url = "http://127.0.0.1:8080/login"
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(
                base_url,
                params={"next": f"/started-{token}"},
                allow_redirects=False,
                timeout=0.5,
            )
            if response.status_code == 302:
                break
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    else:
        pytest.fail(f"run.sh did not start the service on port 8080: {last_error}")

    assert response.headers.get("Location") == f"/started-{token}"
    records = listener_records(8080)
    assert records, "run.sh did not create a listener on port 8080"
    assert any(address == "0100007F" for address, _ in records), \
        "Service must listen on 127.0.0.1:8080"

    listener_pids = pids_for_inodes([inode for _, inode in records])
    cmdlines = []
    for pid in listener_pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdlines.append(f.read().replace(b"\x00", b" ").decode("utf-8", "replace"))
        except OSError:
            pass
    assert any(APP_PATH in cmdline for cmdline in cmdlines), \
        "The port 8080 listener was not launched from the submitted app.py"

    # Exercise the freshly deployed service with additional generated cases.
    deployed_cases = {
        f"/deep/{uuid.uuid4().hex}": None,
        f"http://{uuid.uuid4().hex}.invalid/": "/dashboard",
        f"https://{uuid.uuid4().hex}.invalid/": "/dashboard",
        f"//{uuid.uuid4().hex}.invalid/": "/dashboard",
        uuid.uuid4().hex: "/dashboard",
    }
    for value, expected in deployed_cases.items():
        expected = value if expected is None else expected
        r = requests.get(base_url, params={"next": value}, allow_redirects=False, timeout=2)
        assert r.status_code == 302
        assert r.headers.get("Location") == expected


def test_audit_trail_json():
    log_path = "/home/user/historical_access.log"
    json_path = "/home/user/redirect_audit.json"

    assert os.path.isfile(json_path), f"Audit trail file not found at {json_path}"

    with open(json_path, 'r') as f:
        try:
            audit_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit trail is not valid JSON")

    assert isinstance(audit_data, list), "Audit trail must be a JSON array"

    expected = []
    with open(log_path, 'r') as f:
        for line in f:
            # Parse Nginx combined format
            match = re.search(r'^(\S+) \S+ \S+ \[([^\]]+)\] "GET /login\?next=(http[s]?://[^ ]+) HTTP/[0-9.]+" (200|302) ', line)
            if match:
                ip_address = match.group(1)
                timestamp = match.group(2)
                malicious_target = match.group(3)
                expected.append({
                    "timestamp": timestamp,
                    "ip_address": ip_address,
                    "malicious_target": malicious_target
                })

    assert len(audit_data) == len(expected), f"Expected {len(expected)} records, found {len(audit_data)}"

    for exp in expected:
        assert exp in audit_data, f"Missing expected record in audit trail: {exp}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
