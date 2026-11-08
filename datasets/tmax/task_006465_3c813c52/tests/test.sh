#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import socket
import pytest
import glob
import signal
import subprocess
import time
from pathlib import Path

STATUS_FILE = "/home/user/operator_status.json"
MANIFESTS_DIR = "/home/user/manifests"


def get_actual_manifest_bytes():
    total_size = 0
    pattern = os.path.join(MANIFESTS_DIR, "*.yaml")
    for filepath in glob.glob(pattern):
        if os.path.isfile(filepath):
            total_size += os.path.getsize(filepath)
    return total_size


def is_api_reachable():
    host = "127.0.0.1"
    port = 8080
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex((host, port))
        return result == 0


def test_operator_status_json_exists():
    assert os.path.isfile(STATUS_FILE), f"The file {STATUS_FILE} does not exist."


def test_operator_status_json_content():
    assert os.path.isfile(STATUS_FILE), f"The file {STATUS_FILE} does not exist."

    with open(STATUS_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {STATUS_FILE} does not contain valid JSON.")

    assert "manifest_bytes" in data, "Key 'manifest_bytes' missing in JSON."
    assert "api_reachable" in data, "Key 'api_reachable' missing in JSON."
    assert "status" in data, "Key 'status' missing in JSON."

    expected_bytes = get_actual_manifest_bytes()
    expected_reachable = is_api_reachable()
    expected_status = "healthy" if expected_reachable and expected_bytes <= 1048576 else "unhealthy"

    assert data["manifest_bytes"] == expected_bytes, f"Expected manifest_bytes to be {expected_bytes}, but got {data['manifest_bytes']}."
    assert data["api_reachable"] == expected_reachable, f"Expected api_reachable to be {expected_reachable}, but got {data['api_reachable']}."
    assert data["status"] == expected_status, f"Expected status to be '{expected_status}', but got '{data['status']}'."


def listening_pids(port=8080):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted_port and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[-1])
        try:
            for fd in os.listdir(os.path.join(proc, "fd")):
                try:
                    target = os.readlink(os.path.join(proc, "fd", fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(pid)
                    break
        except OSError:
            pass
    return pids


def stop_api():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listening_pids()
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.25)


def start_api():
    stop_api()
    proc = subprocess.Popen(
        ["python3", "-m", "http.server", "8080", "--bind", "127.0.0.1"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 3
    while time.time() < deadline:
        if is_api_reachable():
            return proc
        if proc.poll() is not None:
            break
        time.sleep(0.05)
    proc.kill()
    raise AssertionError("Verifier could not start its test API server on port 8080")


def candidate_commands():
    roots = ["/home/user", "/root", "/tmp", "/usr/local/bin"]
    excluded = {STATUS_FILE, "/tmp/test_final_state.py"}
    seen = set()

    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in {"__pycache__", "node_modules"}]
            for name in filenames:
                path = os.path.join(directory, name)
                if path in excluded or path.startswith(MANIFESTS_DIR + os.sep):
                    continue
                try:
                    st = os.stat(path)
                    if not os.path.isfile(path) or st.st_size > 5 * 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        raw = f.read()
                except OSError:
                    continue
                if b"operator_status.json" not in raw:
                    continue

                text = raw[:512].decode("utf-8", "ignore")
                suffix = Path(path).suffix.lower()
                commands = []
                if suffix == ".py":
                    commands.append(["python3", path])
                elif suffix in {".sh", ".bash"}:
                    commands.append(["bash", path])
                elif text.startswith("#!"):
                    if "python" in text.splitlines()[0]:
                        commands.append(["python3", path])
                    elif "sh" in text.splitlines()[0] or "bash" in text.splitlines()[0]:
                        commands.append(["bash", path])
                    elif os.access(path, os.X_OK):
                        commands.append([path])
                elif os.access(path, os.X_OK):
                    commands.append([path])
                else:
                    commands.extend((["python3", path], ["bash", path]))

                for command in commands:
                    key = tuple(command)
                    if key not in seen:
                        seen.add(key)
                        yield command


def check_generated_status(expected_bytes, expected_reachable):
    assert os.path.isfile(STATUS_FILE), "The candidate script did not create operator_status.json"
    with open(STATUS_FILE) as f:
        data = json.load(f)
    expected_status = "healthy" if expected_reachable and expected_bytes <= 1048576 else "unhealthy"
    assert data["manifest_bytes"] == expected_bytes
    assert data["api_reachable"] == expected_reachable
    assert data["status"] == expected_status


def exercise_command(command, probe):
    cases = [
        (321, True),
        (1100000, True),
        (321, False),
    ]
    for size, reachable in cases:
        stop_api()
        server = start_api() if reachable else None
        try:
            with open(probe, "wb") as f:
                f.truncate(size)
            expected_bytes = get_actual_manifest_bytes()
            try:
                os.remove(STATUS_FILE)
            except FileNotFoundError:
                pass
            result = subprocess.run(
                command,
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                text=True,
            )
            assert result.returncode == 0, result.stderr[-1000:]
            check_generated_status(expected_bytes, reachable)
        finally:
            if server is not None:
                server.terminate()
                try:
                    server.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    server.kill()


def test_health_check_script_exists_and_performs_diagnostics():
    original_status = None
    if os.path.isfile(STATUS_FILE):
        with open(STATUS_FILE, "rb") as f:
            original_status = f.read()
    originally_reachable = is_api_reachable()
    probe = os.path.join(MANIFESTS_DIR, ".verifier_dynamic_probe.yaml")
    errors = []
    commands = list(candidate_commands())

    try:
        assert commands, "No health-check script that writes operator_status.json was found."
        passed = False
        for command in commands:
            try:
                exercise_command(command, probe)
                passed = True
                break
            except Exception as exc:
                errors.append(f"{' '.join(command)}: {exc}")
        assert passed, "No discovered script passed dynamic diagnostics: " + " | ".join(errors[-5:])
    finally:
        try:
            os.remove(probe)
        except FileNotFoundError:
            pass
        stop_api()
        if originally_reachable:
            start_api()
        if original_status is not None:
            with open(STATUS_FILE, "wb") as f:
                f.write(original_status)
        else:
            try:
                os.remove(STATUS_FILE)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
