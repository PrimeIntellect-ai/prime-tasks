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
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import random
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
AUTH_HEADER = {"Authorization": "Bearer SOC-Analyst-2024"}
RAW_PATH = Path("/home/user/raw_logs.dat")
MAP_PATH = Path("/home/user/ip_map.csv")
IMAGE_PATH = Path("/app/evidence.png")


def request(dept, headers=AUTH_HEADER):
    return requests.get(
        f"{BASE_URL}/api/threats",
        params={"dept": dept},
        headers=headers,
        timeout=5,
    )


def assert_records(dept, expected):
    response = request(dept)
    assert response.status_code == 200, f"Expected 200 for {dept}, got {response.status_code}"
    try:
        actual = response.json()
    except ValueError:
        pytest.fail(f"Response for {dept} is not valid JSON")
    assert isinstance(actual, list), "Response should be a JSON array"
    actual = sorted(actual, key=lambda x: (x.get("timestamp", ""), x.get("ip_address", "")))
    expected = sorted(expected, key=lambda x: (x["timestamp"], x["ip_address"]))
    assert len(actual) == len(expected), f"Expected {len(expected)} records for {dept}, got {len(actual)}"
    for got, want in zip(actual, expected):
        assert int(got.get("error_code", -1)) == want["error_code"]
        for key in ["timestamp", "ip_address", "department", "message"]:
            assert got.get(key) == want[key], f"Mismatch in {key}: expected {want[key]!r}, got {got.get(key)!r}"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "2382" and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            continue
    return None


def stop_listener():
    pid = listener_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if listener_pid() is None:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    for _ in range(30):
        if listener_pid() is None:
            return
        time.sleep(0.1)


def wait_ready(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = request("__readiness__")
            if response.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(0.2)
    pytest.fail("Restarted submitted server did not become ready")


def server_command_and_script():
    pid = listener_pid()
    assert pid is not None, "No process is listening on port 9090"
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    command = [part.decode(errors="surrogateescape") for part in raw if part]
    assert command, "Could not determine server command"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    script = None
    for arg in command[1:]:
        if arg.endswith(".py"):
            candidate = Path(arg)
            if not candidate.is_absolute():
                candidate = Path(cwd) / candidate
            if candidate.is_file():
                script = candidate.resolve()
                break
    assert script is not None, "The listening server was not started from a Python script"
    assert script.stat().st_size > 0, "Submitted Python server script is empty"
    return command, cwd


def derive_expected(log_lines, ip_rows):
    departments = {ip: dept for ip, dept in ip_rows}
    seen = set()
    result = {}
    for line in log_lines:
        timestamp, ip_address, message = line.split("|", 2)
        digest = hashlib.md5((timestamp + ip_address).encode()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        if ip_address not in departments:
            continue
        marker = "ErrCode:"
        code = int(message.split(marker, 1)[1].split()[0])
        department = departments[ip_address]
        result.setdefault(department, []).append({
            "timestamp": timestamp,
            "ip_address": ip_address,
            "department": department,
            "error_code": code,
            "message": message,
        })
    return result


def test_complete_pipeline_and_api():
    # Preserve the original verifier's authorization assertions.
    response = request("Engineering", headers={})
    assert response.status_code == 401, f"Expected 401 without authorization, got {response.status_code}"
    response = request("Engineering", headers={"Authorization": "Bearer Wrong-Token"})
    assert response.status_code == 401, f"Expected 401 for wrong token, got {response.status_code}"

    # Preserve the original fixed-data assertions.
    assert_records("Engineering", [
        {"timestamp": "2024-01-01T10:00:00Z", "ip_address": "192.168.1.10", "department": "Engineering", "error_code": 9021, "message": "Intrusion attempt ErrCode:9021"},
        {"timestamp": "2024-01-01T10:10:00Z", "ip_address": "192.168.1.10", "department": "Engineering", "error_code": 9999, "message": "Data exfiltration ErrCode:9999"},
    ])
    assert_records("Finance", [
        {"timestamp": "2024-01-01T10:05:00Z", "ip_address": "10.0.0.5", "department": "Finance", "error_code": 404, "message": "Malformed packet ErrCode:404"},
    ])
    assert_records("HR", [])

    command, cwd = server_command_and_script()
    backups = {path: path.read_bytes() for path in (RAW_PATH, MAP_PATH, IMAGE_PATH)}
    nonce = f"{random.SystemRandom().randrange(10**8, 10**9)}"
    departments = [f"Blue-{nonce}", f"Red-{nonce}", f"HR-{nonce}"]
    ip_rows = [
        ("10.71.4.11", departments[0]),
        ("10.71.4.12", departments[1]),
        ("10.71.4.13", departments[2]),
    ]
    base = random.SystemRandom().randrange(12000, 60000)
    log_lines = [
        f"2031-07-08T01:02:03Z|10.71.4.11|Probe alpha ErrCode:{base}",
        f"2031-07-08T01:02:03Z|10.71.4.11|Duplicate must vanish ErrCode:{base + 1}",
        f"2031-07-08T01:03:04Z|10.71.4.12|Probe beta ErrCode:{base + 2}",
        f"2031-07-08T01:04:05Z|10.71.4.11|Probe gamma ErrCode:{base + 3}",
        f"2031-07-08T01:05:06Z|10.71.4.13|Probe delta ErrCode:{base + 4}",
    ]
    expected = derive_expected(log_lines, ip_rows)

    restarted = None
    try:
        stop_listener()
        MAP_PATH.write_text(
            "ip_address,department\n" + "".join(f"{ip},{dept}\n" for ip, dept in ip_rows),
            encoding="utf-8",
        )
        RAW_PATH.write_bytes("\n".join(log_lines).encode("utf-16be"))
        subprocess.run([
            "convert", "-size", "500x100", "xc:white", "-fill", "black",
            "-pointsize", "24", "-annotate", "+10+50", "TargetEncoding: utf-16be",
            str(IMAGE_PATH),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        restarted = subprocess.Popen(command, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_ready()

        response = request(departments[0], headers={})
        assert response.status_code == 401
        response = request(departments[0], headers={"Authorization": "Bearer invalid"})
        assert response.status_code == 401
        for department in departments:
            assert_records(department, expected.get(department, []))
        assert_records(f"Absent-{nonce}", [])
    finally:
        stop_listener()
        if restarted is not None and restarted.poll() is None:
            restarted.terminate()
        for path, contents in backups.items():
            path.write_bytes(contents)
        # Restore the submitted server against the original evidence and inputs.
        subprocess.Popen(command, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
