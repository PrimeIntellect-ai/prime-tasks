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
import csv
import json
import os
import re
import secrets
import signal
import subprocess
import time
from datetime import datetime, timedelta

import pytest
import requests

API_URL = "http://127.0.0.1:9055"
TOKEN = "f9a8b7c6"
HEADERS = {"X-Auth-Token": TOKEN}
BASE_PATH = "/app/data/base.csv"
CHANGES_PATH = "/app/data/changes.jsonl"


def get_state(time_str):
    resp = requests.get(f"{API_URL}/api/state?time={time_str}", headers=HEADERS, timeout=3)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}: {resp.text}"
    return resp.json()


def listener_pid(port=9055):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[-1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except OSError:
            continue
    return None


def capture_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert argv, "Listening API process has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for item in f.read().split(b"\0"):
                if b"=" in item:
                    key, value = item.split(b"=", 1)
                    env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    # A Flask debug child cannot be relaunched using its inherited, now-invalid fd.
    env.pop("WERKZEUG_RUN_MAIN", None)
    env.pop("WERKZEUG_SERVER_FD", None)
    return argv, cwd, env


def stop_and_restart_api():
    pid = listener_pid()
    assert pid is not None, "No process is listening on the required port 9055"
    argv, cwd, env = capture_process(pid)

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    deadline = time.time() + 3
    while time.time() < deadline and listener_pid() == pid:
        time.sleep(0.05)
    if listener_pid() == pid:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    # A reloader may have restarted the listener itself. Otherwise execute the
    # exact command that was serving the submitted API, from its original cwd.
    time.sleep(0.3)
    if listener_pid() is None:
        subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(
                f"{API_URL}/api/state?time=2024-01-01T00:00:00",
                headers=HEADERS,
                timeout=1,
            )
            if response.status_code == 200:
                return
            last_error = AssertionError(f"API returned HTTP {response.status_code}")
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Restarted API did not become ready: {last_error}")


def test_cron_file():
    path = "/app/backup.cron"
    assert os.path.isfile(path), f"Cron file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    match = re.search(r"^0\s+2\s+\*\s+\*\s+\*\s+/app/backup\.sh", content, re.MULTILINE)
    assert match is not None, f"Cron file {path} does not contain the correct schedule for 2:00 AM."


def test_api_unauthorized():
    try:
        resp = requests.get(f"{API_URL}/api/state?time=2024-01-01T01:00:00", timeout=3)
        assert resp.status_code == 401, f"Expected 401 Unauthorized without token, got {resp.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to API at {API_URL}. Is the server running?")

    try:
        resp = requests.get(
            f"{API_URL}/api/state?time=2024-01-01T01:00:00",
            headers={"X-Auth-Token": "wrongtoken"}, timeout=3
        )
        assert resp.status_code == 401, f"Expected 401 Unauthorized with wrong token, got {resp.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to API at {API_URL}. Is the server running?")


def test_api_state_base():
    time_str = "2024-01-01T01:00:00"
    data = get_state(time_str)
    assert data.get("auth") == {"cpu": 2, "mem": 1024}, f"Incorrect base state for auth: {data.get('auth')}"
    assert data.get("web") == {"cpu": 4, "mem": 2048}, f"Incorrect base state for web: {data.get('web')}"
    assert data.get("db") == {"cpu": 8, "mem": 8192}, f"Incorrect base state for db: {data.get('db')}"


def test_api_state_web_scaled():
    time_str = "2024-01-01T08:30:00"
    data = get_state(time_str)
    assert data.get("web") == {"cpu": 6, "mem": 4096}, f"Incorrect state for web after scale up: {data.get('web')}"
    assert data.get("db") == {"cpu": 8, "mem": 8192}, f"db state should not have changed yet: {data.get('db')}"


def test_api_state_db_invalid_ignored():
    time_str = "2024-01-01T09:15:00"
    data = get_state(time_str)
    assert data.get("db") == {"cpu": 8, "mem": 8192}, f"Invalid scale down for db should have been ignored. Got: {data.get('db')}"


def test_api_state_auth_unicode_handled():
    time_str = "2024-01-01T11:00:00"
    data = get_state(time_str)
    assert data.get("auth") == {"cpu": 4, "mem": 2048}, f"Auth change with bad unicode should have been parsed and applied. Got: {data.get('auth')}"
    assert data.get("web") == {"cpu": 6, "mem": 4096}, f"Web should still be scaled up: {data.get('web')}"
    assert data.get("db") == {"cpu": 8, "mem": 8192}, f"DB should remain at base state: {data.get('db')}"


def test_api_uses_input_files_and_resamples_general_history():
    with open(BASE_PATH, "rb") as f:
        old_base = f.read()
    with open(CHANGES_PATH, "rb") as f:
        old_changes = f.read()

    suffix = secrets.token_hex(5)
    services = [f"svc_{suffix}_{letter}" for letter in "abcd"]
    bases = {
        service: {"cpu": 2 + i + secrets.randbelow(4), "mem": 512 * (i + 2) + secrets.randbelow(200)}
        for i, service in enumerate(services)
    }
    origin = datetime(2024, 1, 1, 0, 0, 0)
    offsets = [
        1000 + secrets.randbelow(300),
        5000 + secrets.randbelow(300),
        9000 + secrets.randbelow(300),
        50000 + secrets.randbelow(300),
        100000 + secrets.randbelow(300),
    ]
    times = [(origin + timedelta(seconds=n)).replace(microsecond=0) for n in offsets]
    events = [
        {"time": times[0], "service": services[0], "cpu": bases[services[0]]["cpu"] + 7, "mem": bases[services[0]]["mem"] + 777, "valid": True, "bad_note": False},
        {"time": times[1], "service": services[1], "cpu": 0, "mem": bases[services[1]]["mem"] + 999, "valid": False, "bad_note": False},
        {"time": times[2], "service": services[2], "cpu": bases[services[2]]["cpu"] + 5, "mem": bases[services[2]]["mem"] + 1333, "valid": True, "bad_note": True},
        {"time": times[3], "service": services[0], "cpu": bases[services[0]]["cpu"] + 20, "mem": 64, "valid": False, "bad_note": False},
        {"time": times[4], "service": services[3], "cpu": bases[services[3]]["cpu"] + 9, "mem": bases[services[3]]["mem"] + 2049, "valid": True, "bad_note": False},
    ]

    try:
        with open(BASE_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["service", "cpu", "mem"])
            for service in services:
                writer.writerow([service, bases[service]["cpu"], bases[service]["mem"]])

        lines = []
        for event in events:
            record = {
                "time": event["time"].isoformat(),
                "service": event["service"],
                "cpu": event["cpu"],
                "mem": event["mem"],
                "note": "MARKER" if event["bad_note"] else "ordinary change",
            }
            line = json.dumps(record)
            if event["bad_note"]:
                line = line.replace('"MARKER"', '"broken ' + '\\uZZZZ' + ' note"')
            lines.append(line)
        with open(CHANGES_PATH, "w") as f:
            f.write("\n".join(lines) + "\n")

        stop_and_restart_api()

        checkpoints = [origin + timedelta(seconds=30)]
        for event in events:
            checkpoints.append(event["time"])
            checkpoints.append(event["time"] + timedelta(seconds=1))
        checkpoints.append(events[-1]["time"] + timedelta(days=3))

        for checkpoint in checkpoints:
            expected = {service: values.copy() for service, values in bases.items()}
            for event in events:
                if event["valid"] and event["time"] <= checkpoint:
                    expected[event["service"]] = {"cpu": event["cpu"], "mem": event["mem"]}
            actual = get_state(checkpoint.isoformat())
            assert actual == expected, (
                f"Incorrect complete state at {checkpoint.isoformat()}. "
                f"Expected {expected}, got {actual}"
            )
    finally:
        with open(BASE_PATH, "wb") as f:
            f.write(old_base)
        with open(CHANGES_PATH, "wb") as f:
            f.write(old_changes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
