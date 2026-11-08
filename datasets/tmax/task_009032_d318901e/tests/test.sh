#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

SHARED_DATA_DIR = "/home/user/shared_data"
ACL_REPORT = "/home/user/acl_report.txt"
CAPACITY_REPORT = "/home/user/capacity_report.json"
MONITOR_PY = "/home/user/monitor.py"
MONITOR_JS = "/home/user/monitor.js"


def recursive_file_bytes():
    total = 0
    for root, dirs, files in os.walk(SHARED_DATA_DIR, followlinks=False):
        for name in files:
            path = os.path.join(root, name)
            if not os.path.islink(path):
                total += os.path.getsize(path)
    return total


def fetch(port, timeout=2):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200 OK from port {port}."
        raw = response.read().decode()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Response from port {port} is not valid JSON: {exc}")
    assert set(data) == {"usage_bytes"}, f"Unexpected JSON shape from port {port}: {data!r}"
    assert type(data["usage_bytes"]) is int, f"'usage_bytes' from port {port} is not an integer."
    return raw, data


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].split(":")[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(entry))
                    break
        except OSError:
            continue
    return found


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except OSError:
        return []


def wait_for_usage(port, expected, timeout=6):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            _, data = fetch(port)
            if data == {"usage_bytes": expected}:
                return
            last_error = AssertionError(f"port {port} returned {data!r}, expected usage_bytes={expected}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    raise AssertionError(f"Port {port} did not report {expected}: {last_error}")


def test_acl_applied():
    result = subprocess.run(['getfacl', SHARED_DATA_DIR], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run getfacl."
    assert "user:nobody:r-x" in result.stdout, f"ACL for 'nobody' is not correctly set on {SHARED_DATA_DIR}."


def test_acl_report():
    assert os.path.isfile(ACL_REPORT), f"{ACL_REPORT} does not exist."
    with open(ACL_REPORT, 'r') as f:
        content = f.read()
    assert "user:nobody:r-x" in content, f"{ACL_REPORT} does not contain 'user:nobody:r-x'."


def test_capacity_report():
    assert os.path.isfile(CAPACITY_REPORT), f"{CAPACITY_REPORT} does not exist."
    with open(CAPACITY_REPORT, 'r') as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"{CAPACITY_REPORT} is not valid JSON.")
    assert "usage_bytes" in data, f"{CAPACITY_REPORT} missing 'usage_bytes' key."
    assert isinstance(data["usage_bytes"], int), f"'usage_bytes' in {CAPACITY_REPORT} is not an integer."
    assert data["usage_bytes"] > 0, f"'usage_bytes' should be greater than 0."
    assert set(data) == {"usage_bytes"}, f"{CAPACITY_REPORT} has an unexpected JSON shape."
    assert type(data["usage_bytes"]) is int
    assert data["usage_bytes"] == recursive_file_bytes(), "Capacity report does not contain the actual recursive byte usage."


def test_port_9090_responds():
    try:
        _, data = fetch(9090)
        assert data["usage_bytes"] == recursive_file_bytes(), "Port 9090 reports incorrect recursive byte usage."
    except Exception as e:
        pytest.fail(f"Failed to connect to or read from 127.0.0.1:9090. Error: {e}")


def test_port_8080_responds():
    try:
        raw, data = fetch(8080)
        assert data["usage_bytes"] == recursive_file_bytes(), "Port 8080 reports incorrect recursive byte usage."
        with open(CAPACITY_REPORT) as f:
            assert f.read().strip() == raw.strip(), "capacity_report.json is not the response saved from the forwarded endpoint."
    except Exception as e:
        pytest.fail(f"Failed to connect to or read from 127.0.0.1:8080. Error: {e}")


def test_monitor_script_exists():
    py_exists = os.path.isfile(MONITOR_PY)
    js_exists = os.path.isfile(MONITOR_JS)
    assert py_exists or js_exists, "Monitoring script (monitor.py or monitor.js) not found in /home/user/."


def test_monitor_tracks_recursive_usage():
    probe = os.path.join(SHARED_DATA_DIR, f".verifier_probe_{os.getpid()}")
    baseline = recursive_file_bytes()
    payload = os.urandom(1733)
    try:
        with open(probe, "wb") as f:
            f.write(payload)
        expected = recursive_file_bytes()
        assert expected == baseline + len(payload)
        wait_for_usage(9090, expected)
        wait_for_usage(8080, expected)
    finally:
        try:
            os.unlink(probe)
        except FileNotFoundError:
            pass
    wait_for_usage(9090, baseline)
    wait_for_usage(8080, baseline)


def test_zz_8080_is_forwarded_to_9090_and_monitor_is_executable():
    candidates = []
    for pid in listener_pids(9090):
        cmdline = process_cmdline(pid)
        joined = " ".join(cmdline)
        if "monitor.py" in joined and os.path.isfile(MONITOR_PY):
            candidates.append((pid, MONITOR_PY))
        elif "monitor.js" in joined and os.path.isfile(MONITOR_JS):
            candidates.append((pid, MONITOR_JS))
    assert candidates, "Port 9090 is not being served by the required monitoring script."

    pid, artifact = candidates[0]
    expected = recursive_file_bytes()
    server = None
    restarted = None
    forwarded_body = None
    nonce = os.urandom(24).hex().encode()

    class ProbeHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(nonce)))
            self.end_headers()
            self.wfile.write(nonce)

        def log_message(self, format, *args):
            pass

    try:
        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 4
        while listener_pids(9090) and time.time() < deadline:
            time.sleep(0.1)
        if listener_pids(9090):
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.2)
        assert not listener_pids(9090), "Could not temporarily stop the monitor listener."

        server = HTTPServer(("127.0.0.1", 9090), ProbeHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=3) as response:
            forwarded_body = response.read()
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        command = ["python3", artifact] if artifact.endswith(".py") else ["node", artifact]
        restarted = subprocess.Popen(command, cwd="/home/user", stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            wait_for_usage(9090, expected)
            wait_for_usage(8080, expected)
        except Exception:
            restarted.terminate()
            raise

    assert forwarded_body == nonce, "TCP port 8080 is not actually forwarding connections to port 9090."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
