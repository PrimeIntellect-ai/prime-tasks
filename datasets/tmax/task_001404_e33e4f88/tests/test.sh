#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime as dt
import os
import re
import socket
import subprocess
import tempfile
import time
from zoneinfo import ZoneInfo

import pytest

SERVER = "/home/user/server"
SOURCE = "/home/user/server.c"
CONFIG = "/home/user/haproxy.cfg"
BODY_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) ([A-Za-z0-9+\-]+)\n?$")


def unused_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for_port(port, process=None, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            pytest.fail(f"Server exited early with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"Port {port} did not start listening on 127.0.0.1")


def http_request(port):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks)
    assert b"\r\n\r\n" in raw, f"Response is not a valid HTTP response: {raw!r}"
    headers, body = raw.split(b"\r\n\r\n", 1)
    status = headers.split(b"\r\n", 1)[0]
    assert re.fullmatch(rb"HTTP/1\.[01] 200(?: .*)?", status), f"Unexpected HTTP status: {status!r}"
    try:
        return body.decode("ascii")
    except UnicodeDecodeError as exc:
        pytest.fail(f"HTTP body is not ASCII text: {exc}")


def assert_current_timezone_body(body, zone_name):
    match = BODY_RE.fullmatch(body)
    assert match, f"Body has wrong format: {body!r}"
    shown = dt.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    now = dt.datetime.now(ZoneInfo(zone_name))
    assert match.group(2) == now.tzname(), (
        f"Expected timezone abbreviation {now.tzname()} for {zone_name}, got {match.group(2)}"
    )
    expected_local = now.replace(tzinfo=None)
    assert abs((shown - expected_local).total_seconds()) <= 8, (
        f"Response time {shown} is not the current local time in {zone_name}"
    )


def exercise_server(binary, zone_name):
    port = unused_port()
    env = os.environ.copy()
    env["TZ"] = zone_name
    proc = subprocess.Popen(
        [binary, str(port)], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_port(port, proc)
        # Multiple successful connections verify that the server remains persistent.
        for _ in range(2):
            assert_current_timezone_body(http_request(port), zone_name)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def process_records():
    records = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        base = f"/proc/{entry}"
        try:
            exe = os.path.realpath(f"{base}/exe")
            with open(f"{base}/cmdline", "rb") as f:
                cmd = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            with open(f"{base}/environ", "rb") as f:
                env_items = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            env = dict(x.split("=", 1) for x in env_items if "=" in x)
            records.append((int(entry), exe, cmd, env))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    return records


def test_high_latency_ips():
    """Verify that high_latency.txt contains the correct unique IPs."""
    file_path = "/home/user/high_latency.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ips = {"192.168.1.11", "192.168.1.12", "192.168.1.15"}
    actual_ips = set(lines)

    assert len(lines) == 3, f"Expected exactly 3 lines in {file_path}, found {len(lines)}."
    assert actual_ips == expected_ips, f"Expected IPs {expected_ips}, but found {actual_ips}."


def test_c_server_files_exist():
    """Verify that the C source and compiled executable exist."""
    source_path = SOURCE
    exec_path = SERVER

    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."
    assert os.path.isfile(exec_path), f"Executable {exec_path} does not exist."
    assert os.access(exec_path, os.X_OK), f"File {exec_path} is not executable."
    with open(exec_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled server is not an ELF executable."


def test_server_source_and_executable_behavior():
    # Exercise the submitted executable under both required TZ values.
    exercise_server(SERVER, "Asia/Tokyo")
    exercise_server(SERVER, "Europe/London")

    # Compile and exercise the submitted C source so the source itself implements the backend.
    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "server")
        result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"server.c does not compile:\n{result.stderr}"
        exercise_server(rebuilt, "Asia/Tokyo")

    for args in ([], ["12345", "extra"]):
        try:
            result = subprocess.run(
                [SERVER] + args, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Server did not reject invalid argument list: {args}")
        assert result.returncode != 0, f"Server accepted invalid argument list: {args}"


def test_haproxy_config():
    """Verify HAProxy configuration contains expected bindings and backends."""
    config_path = CONFIG
    assert os.path.isfile(config_path), f"HAProxy config {config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:9000" in content or "*:9000" in content or "9000" in content, "HAProxy config missing frontend port 9000."
    assert "9001" in content, "HAProxy config missing backend port 9001."
    assert "9002" in content, "HAProxy config missing backend port 9002."

    active = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r"(?im)^\s*frontend\s+\S+", active), "Missing HAProxy frontend section."
    assert re.search(r"(?im)^\s*bind\s+127\.0\.0\.1:9000(?:\s|$)", active), "Frontend must bind to 127.0.0.1:9000."
    assert re.search(r"(?im)^\s*backend\s+\S+", active), "Missing HAProxy backend section."
    assert re.search(r"(?im)^\s*mode\s+http(?:\s|$)", active), "HAProxy must use HTTP mode."
    assert re.search(r"(?im)^\s*balance\s+roundrobin(?:\s|$)", active), "Backend must use roundrobin balancing."
    assert re.search(r"(?im)^\s*server\s+\S+\s+127\.0\.0\.1:9001(?:\s|$)", active), "Missing backend server at 127.0.0.1:9001."
    assert re.search(r"(?im)^\s*server\s+\S+\s+127\.0\.0\.1:9002(?:\s|$)", active), "Missing backend server at 127.0.0.1:9002."

    checked = subprocess.run(
        ["haproxy", "-c", "-f", CONFIG], capture_output=True, text=True, timeout=10
    )
    assert checked.returncode == 0, f"HAProxy rejects the configuration:\n{checked.stdout}\n{checked.stderr}"


def test_required_services_are_running_and_functional():
    records = process_records()
    server_real = os.path.realpath(SERVER)

    for port, zone in (("9001", "Asia/Tokyo"), ("9002", "Europe/London")):
        matches = [r for r in records if r[1] == server_real and len(r[2]) == 2 and r[2][1] == port]
        assert matches, f"No running /home/user/server process found for port {port}."
        assert any(r[3].get("TZ") == zone for r in matches), f"Server on port {port} is not running with TZ={zone}."
        assert_current_timezone_body(http_request(int(port)), zone)

    haproxy_matches = [
        r for r in records
        if os.path.basename(r[1]).startswith("haproxy")
        and "-f" in r[2]
        and any(os.path.realpath(arg) == os.path.realpath(CONFIG) for arg in r[2])
    ]
    assert haproxy_matches, "HAProxy is not running with /home/user/haproxy.cfg."

    bodies = [http_request(9000) for _ in range(4)]
    zones = []
    for body in bodies:
        match = BODY_RE.fullmatch(body)
        assert match, f"Proxy returned a malformed backend body: {body!r}"
        if match.group(2) == dt.datetime.now(ZoneInfo("Asia/Tokyo")).tzname():
            assert_current_timezone_body(body, "Asia/Tokyo")
            zones.append("Tokyo")
        elif match.group(2) == dt.datetime.now(ZoneInfo("Europe/London")).tzname():
            assert_current_timezone_body(body, "Europe/London")
            zones.append("London")
        else:
            pytest.fail(f"Proxy returned an unexpected timezone: {body!r}")
    assert zones.count("Tokyo") == 2 and zones.count("London") == 2, f"Proxy did not distribute four requests evenly: {zones}"
    assert all(zones[i] != zones[i + 1] for i in range(3)), f"Proxy responses are not round-robin: {zones}"


def test_proxy_results_log():
    """Verify proxy_results.log has exactly 4 lines alternating timezones."""
    log_path = "/home/user/proxy_results.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {log_path}, found {len(lines)}."

    jst_count = 0
    lon_count = 0
    logged_zones = []

    for line in lines:
        assert BODY_RE.fullmatch(line), f"Line '{line}' is not formatted as YYYY-MM-DD HH:MM:SS TZ."
        if "JST" in line:
            jst_count += 1
            logged_zones.append("JST")
        elif "GMT" in line or "BST" in line:
            lon_count += 1
            logged_zones.append("LON")
        else:
            pytest.fail(f"Line '{line}' does not contain expected timezone (JST, GMT, or BST).")

    assert jst_count == 2, f"Expected 2 lines with JST, found {jst_count}."
    assert lon_count == 2, f"Expected 2 lines with GMT/BST, found {lon_count}."
    assert all(logged_zones[i] != logged_zones[i + 1] for i in range(3)), "Logged proxy results do not alternate backends."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
