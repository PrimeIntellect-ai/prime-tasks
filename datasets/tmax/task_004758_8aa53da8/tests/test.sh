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
import glob
import os
import re
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import threading
import time
import secrets

import pytest
import requests


def test_legacy_logs_permissions():
    log_dir = "/home/user/legacy_logs"
    assert os.path.exists(log_dir), f"Directory {log_dir} does not exist."
    st = os.stat(log_dir)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions of {log_dir} are {oct(perms)}, expected 0o700."


def test_logrotate_config():
    config_path = "/home/user/logrotate.conf"
    assert os.path.exists(config_path), f"Logrotate config {config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/home/user/legacy_logs/node.log" in content, "Logrotate config missing target log file."
    assert re.search(r'\bdaily\b', content), "Logrotate config missing 'daily' directive."
    assert re.search(r'\brotate\s+7\b', content), "Logrotate config missing 'rotate 7' directive."
    assert re.search(r'\bcompress\b', content), "Logrotate config missing 'compress' directive."

    # Validate the file with logrotate itself so comments or malformed syntax do not pass.
    result = subprocess.run(
        ["logrotate", "--debug", "--state", "/tmp/logrotate-test.state", config_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, f"logrotate rejected the configuration:\n{result.stdout}"

    # Inspect the effective directives in the block that actually names node.log.
    cleaned = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    matching_bodies = []
    for match in re.finditer(r'([^{}]+)\{([^{}]*)\}', cleaned, re.S):
        header, body = match.groups()
        if "/home/user/legacy_logs/node.log" in header:
            matching_bodies.append(body)
    assert matching_bodies, "No valid logrotate block targets node.log."

    valid = False
    for body in matching_bodies:
        frequency = None
        rotations = None
        compression = None
        for raw in body.splitlines():
            words = raw.strip().split()
            if not words:
                continue
            key = words[0].lower()
            if key in {"hourly", "daily", "weekly", "monthly", "yearly"}:
                frequency = key
            elif key == "rotate" and len(words) >= 2:
                rotations = words[1]
            elif key == "compress":
                compression = True
            elif key == "nocompress":
                compression = False
        if frequency == "daily" and rotations == "7" and compression is True:
            valid = True
            break
    assert valid, "The effective node.log policy must be daily, rotate 7, and compress."


def _read_unit(path):
    sections = {}
    section = None
    pending = ""
    with open(path, encoding="utf-8") as f:
        physical = f.readlines()
    logical = []
    for raw in physical:
        line = raw.rstrip("\n")
        if line.rstrip().endswith("\\"):
            pending += line.rstrip()[:-1] + " "
            continue
        logical.append(pending + line)
        pending = ""
    if pending:
        logical.append(pending)

    for line in logical:
        line = line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            sections.setdefault(section, {})
            continue
        if section and "=" in line:
            key, value = line.split("=", 1)
            sections[section].setdefault(key.strip().lower(), []).append(value.strip())
    return sections


def _assert_executable_execstart(value, unit_name):
    try:
        words = shlex.split(value)
    except ValueError as exc:
        pytest.fail(f"Invalid ExecStart in {unit_name}: {exc}")
    assert words, f"{unit_name} has an empty ExecStart."
    command = words[0].lstrip("-@:+!")
    resolved = command if os.path.isabs(command) else shutil.which(command)
    assert resolved and os.path.isfile(resolved) and os.access(resolved, os.X_OK), \
        f"ExecStart command for {unit_name} is not executable: {command}"


def test_systemd_units_exist_and_are_valid():
    systemd_dir = "/home/user/.config/systemd/user"
    legacy_node_svc = os.path.join(systemd_dir, "legacy-node.service")
    legacy_bridge_svc = os.path.join(systemd_dir, "legacy-bridge.service")

    # Preserve the original existence assertions.
    assert os.path.exists(legacy_node_svc), f"Systemd unit {legacy_node_svc} does not exist."
    assert os.path.exists(legacy_bridge_svc), f"Systemd unit {legacy_bridge_svc} does not exist."

    verify = subprocess.run(
        ["systemd-analyze", "--user", "verify", legacy_node_svc, legacy_bridge_svc],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env={**os.environ, "HOME": "/home/user"},
    )
    assert verify.returncode == 0, f"systemd rejected the user units:\n{verify.stdout}"

    node = _read_unit(legacy_node_svc)
    bridge = _read_unit(legacy_bridge_svc)
    node_execs = node.get("service", {}).get("execstart", [])
    bridge_execs = bridge.get("service", {}).get("execstart", [])
    assert node_execs, "legacy-node.service is missing ExecStart."
    assert bridge_execs, "legacy-bridge.service is missing ExecStart."
    assert any("/app/legacy_data_node" in value for value in node_execs), \
        "legacy-node.service does not start /app/legacy_data_node."
    _assert_executable_execstart(node_execs[-1], "legacy-node.service")
    _assert_executable_execstart(bridge_execs[-1], "legacy-bridge.service")

    unit_fields = bridge.get("unit", {})
    required = " ".join(unit_fields.get("requires", []) + unit_fields.get("wants", [])).split()
    ordered = " ".join(unit_fields.get("after", [])).split()
    assert "legacy-node.service" in required, \
        "legacy-bridge.service must declare a dependency on legacy-node.service."
    assert "legacy-node.service" in ordered, \
        "legacy-bridge.service must start after legacy-node.service."


def test_http_bridge_unauthorized():
    url = "http://127.0.0.1:8080/status"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to bridge service at {url}: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized, got {response.status_code}."

    wrong = requests.get(url, headers={"Authorization": "Bearer wrong-token"}, timeout=5)
    assert wrong.status_code == 401, f"Wrong bearer token returned HTTP {wrong.status_code}, expected 401."


def test_http_bridge_authorized():
    url = "http://127.0.0.1:8080/status"
    headers = {"Authorization": "Bearer cloud-migration-token"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to bridge service at {url}: {e}")

    # Preserve the original assertions.
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
    assert "DATA_NODE_OK_V9" in response.text, \
        f"Expected 'DATA_NODE_OK_V9' in response body, got {response.text!r}."


def _kill_legacy_processes():
    victims = []
    for entry in glob.glob("/proc/[0-9]*/exe"):
        try:
            if os.path.realpath(entry) == "/app/legacy_data_node":
                victims.append(int(entry.split("/")[2]))
        except (FileNotFoundError, PermissionError, ValueError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_bridge_really_relays_to_legacy_tcp_service():
    # Replace the legacy process with a verifier-controlled one-time server. Its
    # unpredictable response cannot be hardcoded by a bridge implementation.
    _kill_legacy_processes()
    payload = ("VERIFIER_DYNAMIC_" + secrets.token_hex(24) + "\n").encode()
    observed = {}
    ready = threading.Event()
    finished = threading.Event()

    def fake_legacy():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        deadline = time.time() + 5
        while True:
            try:
                server.bind(("127.0.0.1", 7331))
                break
            except OSError:
                _kill_legacy_processes()
                if time.time() >= deadline:
                    observed["error"] = "Could not take control of TCP port 7331"
                    ready.set()
                    finished.set()
                    server.close()
                    return
                time.sleep(0.05)
        server.listen(1)
        server.settimeout(8)
        ready.set()
        try:
            conn, _ = server.accept()
            with conn:
                conn.settimeout(3)
                observed["command"] = conn.recv(1024)
                conn.sendall(payload)
        except Exception as exc:
            observed["error"] = repr(exc)
        finally:
            server.close()
            finished.set()

    thread = threading.Thread(target=fake_legacy, daemon=True)
    thread.start()
    assert ready.wait(6), "Verifier-controlled legacy server did not start."
    assert "error" not in observed, observed.get("error")

    try:
        response = requests.get(
            "http://127.0.0.1:8080/status",
            headers={"Authorization": "Bearer cloud-migration-token"},
            timeout=7,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Bridge failed while relaying to the controlled legacy service: {exc}")

    assert finished.wait(8), "Bridge never connected to the legacy TCP port."
    assert "error" not in observed, f"Controlled legacy server failed: {observed.get('error')}"
    assert observed.get("command", b"").strip() == b"STATUS_CHECK", \
        f"Bridge sent the wrong legacy command: {observed.get('command')!r}"
    assert response.status_code == 200, f"Expected relayed HTTP 200, got {response.status_code}."
    assert response.content == payload, \
        f"Bridge did not return the exact legacy response: {response.content!r} != {payload!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
