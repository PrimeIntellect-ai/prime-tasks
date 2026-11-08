#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

HOME = "/home/user"
APP = "/home/user/edge_app/app.py"
CONFIG = "/home/user/haproxy.cfg"
DEPLOY = "/home/user/deploy.py"
PID_LOG = "/home/user/pids.log"
EXPECTED = {
    "alpha": (9001, "alpha"),
    "beta": (9002, "beta"),
    "gamma": (9003, "gamma"),
}


def live(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            fields = f.read().split()
        return len(fields) > 2 and fields[2] != "Z"
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False


def read_existing_pids():
    result = set()
    try:
        with open(PID_LOG) as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) == 2 and parts[1].isdigit():
                    pid = int(parts[1])
                    if live(pid):
                        result.add(pid)
    except OSError:
        pass
    return result


def run_as_user(command, timeout):
    account = pwd.getpwnam("user")

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env.update({
        "HOME": HOME,
        "USER": "user",
        "LOGNAME": "user",
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    })
    return subprocess.run(
        command,
        cwd=HOME,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
        preexec_fn=demote,
    )


def parse_pid_log():
    assert os.path.exists(PID_LOG), f"File {PID_LOG} does not exist."
    with open(PID_LOG) as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == 4, f"Expected exactly 4 lines in {PID_LOG}, found {len(raw_lines)}."
    assert all(line.strip() for line in raw_lines), f"Blank line found in {PID_LOG}."

    expected_keys = {"alpha", "beta", "gamma", "haproxy"}
    found_keys = set()
    pids = {}
    for raw_line in raw_lines:
        line = raw_line.strip()
        parts = line.split(":")
        assert len(parts) == 2, f"Invalid line format in {PID_LOG}: '{line}'. Expected 'identifier:pid'."
        key, pid_str = parts
        assert key in expected_keys, f"Unexpected identifier '{key}' in {PID_LOG}. Expected one of {expected_keys}."
        assert key not in found_keys, f"Duplicate identifier '{key}' in {PID_LOG}."
        found_keys.add(key)
        assert pid_str.isdigit(), f"PID for {key} is not a valid number: '{pid_str}'."
        pid = int(pid_str)
        assert os.path.exists(f"/proc/{pid}"), f"Process for '{key}' with PID {pid} is not running."
        assert live(pid), f"Process for '{key}' with PID {pid} is not live."
        pids[key] = pid

    assert found_keys == expected_keys, f"Missing identifiers in {PID_LOG}: {expected_keys - found_keys}."
    assert len(set(pids.values())) == 4, "All four pids.log entries must identify distinct processes."
    return pids


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]


def proc_environ(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    result = {}
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            result[key.decode(errors="replace")] = value.decode(errors="replace")
    return result


def proc_uid(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("Uid:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine UID for PID {pid}")


def listening_inodes(port):
    wanted = f"{port:04X}"
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                    result.add(fields[9])
    return result


def process_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def assert_owns_listener(pid, port):
    inodes = listening_inodes(port)
    assert inodes, f"No process is listening on port {port}."
    assert inodes & process_socket_inodes(pid), f"PID {pid} does not own the listening socket on port {port}."


def get_json(url):
    request = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(request, timeout=2) as response:
        assert response.status == 200, f"Expected HTTP status 200, got {response.status}."
        body = response.read().decode("utf-8")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {body}")


@pytest.fixture(scope="module")
def deployed_pids():
    for path in (APP, CONFIG, DEPLOY):
        assert os.path.isfile(path), f"Required file {path} does not exist or is not a regular file."

    with open(CONFIG, errors="replace") as f:
        config_text = f.read()
    assert re.search(r"(?im)^\s*pidfile\s+/home/user/haproxy\.pid\s*(?:#.*)?$", config_text), \
        "haproxy.cfg must set pidfile to /home/user/haproxy.pid."
    assert re.search(r"(?im)^\s*balance\s+roundrobin\s*(?:#.*)?$", config_text), \
        "haproxy.cfg must configure round-robin balancing."

    check = subprocess.run(
        ["/usr/sbin/haproxy", "-c", "-f", CONFIG],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert check.returncode == 0, f"Invalid HAProxy configuration:\n{check.stdout}"

    old_pids = read_existing_pids()
    try:
        result = run_as_user(["/usr/bin/python3", DEPLOY], timeout=45)
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.py did not finish within 45 seconds.")
    assert result.returncode == 0, f"deploy.py exited with status {result.returncode}."

    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            pids = parse_pid_log()
            if all(live(pid) for pid in pids.values()):
                break
        except AssertionError as error:
            last_error = error
        time.sleep(0.2)
    else:
        if last_error:
            raise last_error
        pytest.fail("Services did not become ready after deploy.py ran.")

    assert not (set(pids.values()) & old_pids), \
        "deploy.py reused previously running logged processes instead of terminating and replacing them."
    return pids


def test_required_processes_and_direct_backends(deployed_pids):
    user_uid = pwd.getpwnam("user").pw_uid

    for key, (port, sensor_id) in EXPECTED.items():
        pid = deployed_pids[key]
        cmdline = proc_cmdline(pid)
        assert any(os.path.realpath(arg) == APP for arg in cmdline if arg), \
            f"PID logged for {key} is not an instance of {APP}: {cmdline}"
        assert os.path.basename(os.readlink(f"/proc/{pid}/exe")).startswith("python"), \
            f"PID logged for {key} is not a Python process."
        environment = proc_environ(pid)
        assert environment.get("PORT") == str(port), f"{key} process does not have PORT={port}."
        assert environment.get("SENSOR_ID") == sensor_id, f"{key} process does not have SENSOR_ID={sensor_id}."
        assert proc_uid(pid) == user_uid, f"{key} is not running as the unprivileged user."
        assert_owns_listener(pid, port)
        assert get_json(f"http://127.0.0.1:{port}/health") == {"sensor_id": sensor_id, "status": "ok"}

    haproxy_pid = deployed_pids["haproxy"]
    haproxy_cmdline = proc_cmdline(haproxy_pid)
    assert os.path.basename(os.readlink(f"/proc/{haproxy_pid}/exe")) == "haproxy", \
        f"PID logged for haproxy is not HAProxy: {haproxy_cmdline}"
    assert CONFIG in haproxy_cmdline, f"HAProxy PID was not started with {CONFIG}: {haproxy_cmdline}"
    assert proc_uid(haproxy_pid) == user_uid, "HAProxy is not running as the unprivileged user."
    assert_owns_listener(haproxy_pid, 9000)

    assert os.path.isfile("/home/user/haproxy.pid"), "HAProxy pidfile was not created."
    with open("/home/user/haproxy.pid") as f:
        pidfile_value = f.read().strip()
    assert pidfile_value == str(haproxy_pid), \
        f"HAProxy pidfile contains {pidfile_value!r}, expected {haproxy_pid}."


def test_pids_log_and_processes(deployed_pids):
    """Verify pids.log format and that the referenced processes are running."""
    assert set(deployed_pids) == {"alpha", "beta", "gamma", "haproxy"}
    for key, pid in deployed_pids.items():
        assert os.path.exists(f"/proc/{pid}"), f"Process for '{key}' with PID {pid} is not running."


def test_haproxy_routing(deployed_pids):
    """Verify HAProxy is load balancing across all three backend instances."""
    url = "http://127.0.0.1:9000/health"
    seen_sensors = set()

    for _ in range(15):
        try:
            data = get_json(url)
            assert "sensor_id" in data, f"Response JSON missing 'sensor_id' key: {data}"
            assert data.get("status") == "ok", f"Expected status 'ok' in JSON, got '{data.get('status')}'."
            seen_sensors.add(data["sensor_id"])
        except urllib.error.URLError as error:
            pytest.fail(f"Failed to connect to HAProxy at {url}: {error}")
        except Exception as error:
            pytest.fail(f"Unexpected error during HTTP request: {error}")
        time.sleep(0.1)

    expected_sensors = {"alpha", "beta", "gamma"}
    missing = expected_sensors - seen_sensors
    assert not missing, f"Load balancing failed. Did not receive responses from instances: {missing}. Seen: {seen_sensors}"
    assert seen_sensors == expected_sensors, f"Unexpected sensor IDs returned through HAProxy: {seen_sensors}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
