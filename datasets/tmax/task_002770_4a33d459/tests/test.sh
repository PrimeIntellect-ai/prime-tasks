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
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8333/exfiltration-report"


def get_report():
    response = None
    last_error = None
    for _ in range(10):
        try:
            response = requests.get(URL, timeout=2)
            break
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.5)
    if response is None:
        pytest.fail(f"Failed to connect to {URL}: {last_error}")
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")


def assert_exact_report(data, target_ip, hourly):
    assert isinstance(data, dict), "Report must be a JSON object"
    assert set(data) == {"investigator", "target_ip", "hourly_exfiltration"}, (
        f"Report has missing or extra fields: {set(data)}"
    )
    assert data["investigator"] == "log-analyst-1"
    assert data["target_ip"] == target_ip
    assert isinstance(data["hourly_exfiltration"], dict)
    assert data["hourly_exfiltration"] == hourly, (
        f"Expected hourly_exfiltration {hourly}, got {data['hourly_exfiltration']}"
    )
    assert all(isinstance(v, int) and not isinstance(v, bool) for v in hourly.values())


def listener_pid(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9:
                local_port = int(fields[1].split(":")[1], 16)
                state = fields[3]
                if local_port == port and state == "0A":
                    inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    return int(proc.name)
        except OSError:
            continue
    return None


def capture_process(pid):
    proc = Path(f"/proc/{pid}")
    argv = [x.decode("utf-8", "surrogateescape") for x in (proc / "cmdline").read_bytes().split(b"\0") if x]
    assert argv, "Could not determine the server command"
    executable = os.readlink(proc / "exe")
    assert "python" in os.path.basename(executable).lower(), "The listener must be a Python HTTP server"
    cwd = os.readlink(proc / "cwd")
    env = os.environ.copy()
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode("utf-8", "replace")] = value.decode("utf-8", "replace")
    return argv, cwd, env


def wait_for_port_closed(port):
    deadline = time.time() + 5
    while time.time() < deadline:
        with socket.socket() as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) != 0:
                return
        time.sleep(0.1)
    pytest.fail(f"Port {port} did not close after stopping the submitted server")


def test_exfiltration_report():
    # Preserve the original fixture assertions while enforcing the strict template.
    original = get_report()
    assert_exact_report(
        original,
        "192.168.55.104",
        {"2023-10-04T08": 7500, "2023-10-04T09": 8000},
    )

    pid = listener_pid(8333)
    assert pid is not None, "Could not identify the process listening on port 8333"
    argv, cwd, env = capture_process(pid)

    # Replace both forensic inputs with an unpredictable second incident, then
    # execute the submitted server again. This rejects a canned fixture response.
    octets = [secrets.randbelow(180) + 20 for _ in range(3)]
    target_ip = f"10.{octets[0]}.{octets[1]}.{octets[2]}"
    base = secrets.randbelow(50000) + 1000
    values = [base + secrets.randbelow(10000) for _ in range(5)]
    hourly = {
        "2024-07-19T03": values[0] + values[1],
        "2024-07-19T04": values[2],
        "2024-07-19T06": values[3] + values[4],
    }

    subprocess.run(
        ["espeak", "-w", "/app/incident_comms.wav", f"Focus the extraction on target IP {target_ip}"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    lines = [
        f"[2024-07-19T03:01:02Z] Connection from IP: {target_ip} - payload size: {values[0]} bytes\n",
        f"[2024-07-19T03:59:58Z] Connection from IP: {target_ip} - payload size: {values[1]} bytes\n",
        f"[2024-07-19T04:15:00Z] Connection from IP: 203.0.113.9 - payload size: 999999 bytes\n",
        f"[2024-07-19T04:22:31Z] Connection from IP: {target_ip} - payload size: {values[2]} bytes \u201cspecial\u201d\n",
        "unstructured noise that must be ignored\n",
        f"[2024-07-19T06:00:00Z] Connection from IP: {target_ip} - payload size: {values[3]} bytes\n",
        f"[2024-07-19T06:44:12Z] Connection from IP: {target_ip} - payload size: {values[4]} bytes\n",
        f"[2024-07-19T07:00:00Z] Connection from IP: 198.51.100.4 - payload size: {base} bytes\n",
    ]
    Path("/app/raw_traffic_logs.txt").write_bytes("".join(lines).encode("cp1252"))

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and Path(f"/proc/{pid}").exists():
        time.sleep(0.05)
    if Path(f"/proc/{pid}").exists():
        os.kill(pid, signal.SIGKILL)
    wait_for_port_closed(8333)

    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    regenerated = get_report()
    assert_exact_report(regenerated, target_ip, hourly)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
