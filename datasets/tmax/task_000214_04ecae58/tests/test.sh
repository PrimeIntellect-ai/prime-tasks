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
import secrets
import shutil
import signal
import socket
import sqlite3
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:9090/breaches"
VALID_TOKEN = "Bearer AUDIT_TOKEN_2024"


def test_server_running_and_unauthorized_without_header():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running on 127.0.0.1:9090 or endpoint /breaches is not exposed.")

    assert response.status_code == 401, f"Expected status code 401 without Authorization header, got {response.status_code}"


def test_server_unauthorized_with_invalid_header():
    headers = {"Authorization": "Bearer WRONG_TOKEN"}
    response = requests.get(URL, headers=headers, timeout=5)
    assert response.status_code == 401, f"Expected status code 401 with invalid Authorization header, got {response.status_code}"


def test_server_returns_correct_data():
    headers = {"Authorization": VALID_TOKEN}
    response = requests.get(URL, headers=headers, timeout=5)

    assert response.status_code == 200, f"Expected status code 200 with valid Authorization header, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON.")

    expected_data = [
        {
            "timestamp": 1730000008,
            "chain": ["Eve", "Frank", "Diana"]
        },
        {
            "timestamp": 1730000004,
            "chain": ["Alice", "Bob", "Diana"]
        }
    ]

    assert data == expected_data, f"Expected JSON response {expected_data}, but got {data}"


def listening_pid(port):
    wanted_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        wanted_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for procdir in glob.glob("/proc/[0-9]*"):
        fd_dir = os.path.join(procdir, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in wanted_inodes:
                    return int(os.path.basename(procdir))
        except (FileNotFoundError, PermissionError):
            continue
    return None


def process_details(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        command = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    cwd = os.readlink(f"/proc/{pid}/cwd")
    environment = os.environ.copy()
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for item in f.read().split(b"\0"):
                if b"=" in item:
                    key, value = item.split(b"=", 1)
                    environment[key.decode(errors="ignore")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return command, cwd, environment


def stop_listener(port):
    pid = listening_pid(port)
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline and listening_pid(port) is not None:
        time.sleep(0.1)
    pid = listening_pid(port)
    if pid is not None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pid(port) is not None:
        time.sleep(0.05)


def wait_for_server(timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(URL, timeout=0.5)
            if response.status_code in (200, 401):
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Re-executed server did not listen on 127.0.0.1:9090: {last_error}")


def entry_script(command, cwd):
    for arg in command[1:]:
        if arg.endswith(".py"):
            path = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
            path = os.path.realpath(path)
            if os.path.isfile(path):
                return path
    return None


def create_random_fixture(red_seconds):
    video_path = "/app/security_cam.mp4"
    try:
        os.unlink(video_path)
    except FileNotFoundError:
        pass

    writer = cv2.VideoWriter(video_path, cv2.VideoWriter_fourcc(*"mp4v"), 1, (320, 240))
    assert writer.isOpened(), "Could not create verifier video fixture"
    for second in range(10):
        frame = np.zeros((240, 320, 3), dtype=np.uint8)
        if second in red_seconds:
            frame[:] = (0, 0, 255)
        else:
            frame[:] = (20 + second, 35 + second, 50 + second)
        writer.write(frame)
    writer.release()

    suffix = secrets.token_hex(6)
    conn = sqlite3.connect("/app/compliance.db")
    try:
        conn.execute("DELETE FROM access_logs")
        conn.execute("DELETE FROM employees")
        employees = [(1, f"CEO_{suffix}", None)]
        logs = []
        next_id = 2
        for second in range(10):
            manager_id = next_id
            worker_id = next_id + 1
            next_id += 2
            employees.append((manager_id, f"Manager_{second}_{suffix}", 1))
            employees.append((worker_id, f"Worker_{second}_{suffix}", manager_id))
            logs.append((1000 + second, worker_id, 1730000000 + second, "MAIN_VAULT"))
        logs.append((2000, 2, 1730000000 + red_seconds[0], "LOBBY"))
        conn.executemany("INSERT INTO employees(emp_id, name, manager_id) VALUES (?, ?, ?)", employees)
        conn.executemany("INSERT INTO access_logs(id, emp_id, timestamp, resource) VALUES (?, ?, ?, ?)", logs)
        conn.commit()
    finally:
        conn.close()


def derive_expected_from_artifacts():
    capture = cv2.VideoCapture("/app/security_cam.mp4")
    assert capture.isOpened(), "Verifier could not read security_cam.mp4"
    red_seconds = []
    index = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        mean_bgr = frame.mean(axis=(0, 1))
        deviation = frame.std(axis=(0, 1)).max()
        if mean_bgr[2] > 240 and mean_bgr[1] < 15 and mean_bgr[0] < 15 and deviation < 8:
            red_seconds.append(index)
        index += 1
    capture.release()

    timestamps = {1730000000 + second for second in red_seconds}
    conn = sqlite3.connect("/app/compliance.db")
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            "SELECT emp_id, timestamp FROM access_logs NOT INDEXED WHERE resource = 'MAIN_VAULT'"
        ).fetchall()
        employees = {
            row["emp_id"]: (row["name"], row["manager_id"])
            for row in conn.execute("SELECT emp_id, name, manager_id FROM employees")
        }
    finally:
        conn.close()

    expected = []
    for row in rows:
        if row["timestamp"] not in timestamps:
            continue
        chain = []
        current = row["emp_id"]
        seen = set()
        while current is not None:
            assert current not in seen and current in employees, "Invalid management hierarchy in fixture"
            seen.add(current)
            name, current = employees[current]
            chain.append(name)
        expected.append({"timestamp": row["timestamp"], "chain": chain})
    return sorted(expected, key=lambda item: item["timestamp"], reverse=True)


def test_reexecute_submission_against_unseen_artifacts():
    pid = listening_pid(9090)
    assert pid is not None, "No process is listening on port 9090"
    command, cwd, environment = process_details(pid)
    script = entry_script(command, cwd)
    assert script is not None, "The listening server must be backed by a runnable Python script"

    with open(script, "r", errors="ignore") as f:
        source = f.read()
    assert re.search(r"\bNOT\s+INDEXED\b|\bDROP\s+INDEX(?:\s+IF\s+EXISTS)?\s+idx_time\b", source, re.I), \
        "Server implementation does not explicitly bypass or drop the corrupted idx_time index"

    video_backup = "/tmp/security_cam.original.mp4"
    db_backup = "/tmp/compliance.original.db"
    shutil.copy2("/app/security_cam.mp4", video_backup)
    shutil.copy2("/app/compliance.db", db_backup)

    replacement = None
    try:
        stop_listener(9090)
        choices = list(range(10))
        first = secrets.randbelow(len(choices))
        red_one = choices.pop(first)
        red_two = choices.pop(secrets.randbelow(len(choices)))
        red_seconds = sorted((red_one, red_two))
        create_random_fixture(red_seconds)
        expected = derive_expected_from_artifacts()

        replacement = subprocess.Popen(
            command,
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        wait_for_server()

        assert requests.get(URL, timeout=5).status_code == 401
        assert requests.get(URL, headers={"Authorization": "Bearer WRONG_TOKEN"}, timeout=5).status_code == 401
        response = requests.get(URL, headers={"Authorization": VALID_TOKEN}, timeout=5)
        assert response.status_code == 200
        assert response.json() == expected, \
            f"Endpoint did not derive breaches from the unseen video/database fixture: expected {expected}, got {response.text}"
    finally:
        stop_listener(9090)
        if replacement is not None and replacement.poll() is None:
            try:
                os.killpg(replacement.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        shutil.copy2(video_backup, "/app/security_cam.mp4")
        shutil.copy2(db_backup, "/app/compliance.db")
        subprocess.Popen(
            command,
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
