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
import os
import json
import re
import socket
import subprocess
import time
import requests
import pytest
from collections import defaultdict

BASHTTPD = "/app/bashttpd-master/bashttpd"
STATS_PATH = "/home/user/stats.json"


def compute_expected_stats():
    log_path = "/home/user/access.log"
    if not os.path.exists(log_path):
        pytest.fail(f"Log file {log_path} is missing, cannot compute expected stats.")

    with open(log_path, "r") as f:
        lines = f.readlines()

    # Remove exact duplicates while preserving order
    unique_lines = list(dict.fromkeys(lines))
    stats = defaultdict(lambda: {
        "total_requests": 0,
        "error_count": 0,
        "response_time_sum": 0,
    })
    pattern = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}):\d{2}\] \S+ "[^"]+" (\d+) (\d+)')

    for line in unique_lines:
        match = pattern.search(line.strip())
        if match:
            minute, status_str, time_str = match.groups()
            status = int(status_str)
            time_ms = int(time_str)
            stats[minute]["total_requests"] += 1
            if status >= 400:
                stats[minute]["error_count"] += 1
            stats[minute]["response_time_sum"] += time_ms

    result = []
    for minute in sorted(stats.keys()):
        data = stats[minute]
        result.append({
            "minute": minute,
            "total_requests": data["total_requests"],
            "error_count": data["error_count"],
            "avg_response_time": data["response_time_sum"] // data["total_requests"],
        })
    return result


@pytest.fixture(scope="module")
def expected_stats():
    return compute_expected_stats()


def split_http_response(raw):
    if b"\r\n\r\n" in raw:
        return raw.split(b"\r\n\r\n", 1)
    if b"\n\n" in raw:
        return raw.split(b"\n\n", 1)
    pytest.fail("bashttpd did not produce a complete HTTP response")


def proc_info():
    info = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/status", "r") as f:
                status = f.read()
            match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
            ppid = int(match.group(1)) if match else 0
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            info[int(name)] = (ppid, cmdline)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return info


def listener_pids_on_loopback_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for row in rows:
            fields = row.split()
            local, state, inode = fields[1], fields[3], fields[9]
            address, port = local.split(":")
            if int(port, 16) != 8080 or state != "0A":
                continue
            is_loopback = address == "0100007F" or address == "00000000000000000000000001000000"
            if is_loopback:
                inodes.add(inode)

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except (FileNotFoundError, PermissionError):
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def related_to_listener(pid, listeners, info):
    ancestors = set()
    current = pid
    while current > 1 and current in info:
        ancestors.add(current)
        current = info[current][0]

    for listener in listeners:
        current = listener
        while current > 1 and current in info:
            if current in ancestors:
                return True
            current = info[current][0]
    return False


def test_stats_json_file(expected_stats):
    """Check if the stats.json file is correctly generated."""
    assert os.path.isfile(STATS_PATH), f"File {STATS_PATH} is missing."
    with open(STATS_PATH, "r") as f:
        try:
            actual_stats = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {STATS_PATH} does not contain valid JSON.")
    assert actual_stats == expected_stats, f"Data in {STATS_PATH} does not match expected output."


def test_bashttpd_artifact_and_uri_routing():
    """Execute the repaired Bash artifact directly and exercise its /stats route."""
    assert os.path.isfile(BASHTTPD), f"Missing required server artifact {BASHTTPD}"
    assert os.access(BASHTTPD, os.X_OK), f"{BASHTTPD} is not executable"
    with open(BASHTTPD, "rb") as f:
        first_line = f.readline().lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "bashttpd is no longer a Bash server"

    request = b"GET /stats HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
    try:
        completed = subprocess.run(
            [BASHTTPD], input=request, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5, check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Direct execution of bashttpd timed out")

    assert completed.returncode == 0, f"bashttpd exited with {completed.returncode}: {completed.stderr!r}"
    headers, body = split_http_response(completed.stdout)
    header_lines = re.split(br"\r?\n", headers)
    assert re.match(br"^HTTP/\d(?:\.\d)? 200(?: |$)", header_lines[0]), "bashttpd did not route GET /stats to a 200 response"
    assert any(re.match(br"(?i)^Content-Type\s*:\s*application/json(?:\s*;.*)?$", line) for line in header_lines[1:]), "Direct bashttpd response lacks Content-Type: application/json"
    with open(STATS_PATH, "rb") as f:
        expected_body = f.read()
    assert body == expected_body, "Direct bashttpd response body is not the exact stats.json bytes"


def test_loopback_listener_uses_bashttpd():
    """Require the loopback listener to invoke the vendored bashttpd artifact."""
    listeners = listener_pids_on_loopback_8080()
    assert listeners, "No process is listening specifically on 127.0.0.1:8080"

    probe = socket.create_connection(("127.0.0.1", 8080), timeout=2)
    try:
        # Keeping the request line incomplete leaves inetd-style bashttpd handlers alive
        # long enough to establish their relationship to the listener.
        probe.sendall(b"GET /stats HTTP/1.1")
        time.sleep(0.25)
        info = proc_info()
        related = []
        for pid, (_, cmdline) in info.items():
            if "bashttpd" in cmdline and related_to_listener(pid, listeners, info):
                related.append((pid, cmdline))
        # socat's listener command itself normally contains EXEC:.../bashttpd.
        for pid in listeners:
            cmdline = info.get(pid, (0, ""))[1]
            if "bashttpd" in cmdline:
                related.append((pid, cmdline))
        assert related, "The port 8080 listener is not invoking bashttpd"
    finally:
        probe.close()


def test_http_server_stats(expected_stats):
    """Check if the HTTP server is running and serves the correct stats."""
    url = "http://127.0.0.1:8080/stats"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"

    try:
        actual_stats = response.json()
    except ValueError:
        pytest.fail("HTTP response body is not valid JSON.")
    assert actual_stats == expected_stats, "HTTP response JSON does not match expected output."

    with open(STATS_PATH, "rb") as f:
        expected_body = f.read()
    assert response.content == expected_body, "HTTP response body is not the exact contents of stats.json"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
