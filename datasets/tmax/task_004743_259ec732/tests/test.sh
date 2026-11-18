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
import ast
import glob
import math
import os
import signal
import stat
import subprocess
import time
from datetime import datetime, timedelta, timezone

import pytest
import requests

REPO_PATH = "/home/user/monitor_repo"
SERVER_PATH = os.path.join(REPO_PATH, "server.py")
URL = "http://127.0.0.1:8080/api/v1/sla"
AUTH_HEADERS = {
    "Authorization": "Bearer uptime-token-2024",
    "Content-Type": "application/json",
}


def _listener_inodes(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local_address = fields[1]
            state = fields[3]
            try:
                local_port = int(local_address.rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port and state == "0A":
                inodes.add(fields[9])
    return inodes


def _listener_pids(port=8080):
    inodes = _listener_inodes(port)
    pids = set()
    if not inodes:
        return pids
    for proc_dir in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(os.path.basename(proc_dir))
        except ValueError:
            continue
        for fd in glob.glob(os.path.join(proc_dir, "fd", "*")):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def _stop_existing_service():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = _listener_pids(8080)
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        deadline = time.time() + 2
        while time.time() < deadline and _listener_pids(8080):
            time.sleep(0.05)
    assert not _listener_pids(8080), "Could not stop the pre-existing service on port 8080."


def _listening_addresses(port=8080):
    addresses = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 4 or fields[3] != "0A":
                continue
            address, port_hex = fields[1].rsplit(":", 1)
            if int(port_hex, 16) == port:
                addresses.append((table, address))
    return addresses


@pytest.fixture(scope="module", autouse=True)
def submitted_service():
    assert os.path.exists(SERVER_PATH), f"{SERVER_PATH} does not exist."
    assert not os.path.islink(SERVER_PATH), f"{SERVER_PATH} must be a regular source file, not a symlink."
    assert stat.S_ISREG(os.stat(SERVER_PATH).st_mode), f"{SERVER_PATH} is not a regular file."
    with open(SERVER_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=SERVER_PATH)

    _stop_existing_service()
    proc = subprocess.Popen(
        ["python3", SERVER_PATH],
        cwd=REPO_PATH,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Submitted server.py exited before serving requests (exit code {proc.returncode}).")
        try:
            requests.get("http://127.0.0.1:8080/", timeout=0.3)
            break
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    else:
        proc.terminate()
        pytest.fail(f"Submitted server.py did not start on 127.0.0.1:8080: {last_error}")

    listeners = _listening_addresses(8080)
    assert ("/proc/net/tcp", "0100007F") in listeners, \
        f"Service is not bound specifically to IPv4 127.0.0.1:8080; listeners were {listeners}."
    assert ("/proc/net/tcp", "00000000") not in listeners, \
        "Service must not expose port 8080 on all IPv4 interfaces."
    assert ("/proc/net/tcp6", "00000000000000000000000000000000") not in listeners, \
        "Service must not expose port 8080 on all IPv6 interfaces."

    yield

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_failure_frame():
    frame_file = "/home/user/failure_frame.txt"
    assert os.path.isfile(frame_file), f"File {frame_file} does not exist."
    with open(frame_file, "r") as f:
        content = f.read().strip()
    assert content == "142", f"Expected failure frame to be 142, but got '{content}'."


def test_bad_commit():
    commit_file = "/home/user/bad_commit.txt"
    repo_path = "/home/user/monitor_repo"

    assert os.path.isfile(commit_file), f"File {commit_file} does not exist."
    with open(commit_file, "r") as f:
        submitted_hash = f.read().strip()

    try:
        git_log = subprocess.check_output(
            ["git", "-C", repo_path, "log", "--reverse", "--format=%H"],
            text=True,
        )
        commits = git_log.strip().split("\n")
        assert len(commits) >= 3, "Repository does not have enough commits."
        expected_hash = commits[2].strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run git command in {repo_path}: {e}")

    assert submitted_hash == expected_hash, f"Expected bad commit hash {expected_hash}, but got {submitted_hash}."


def _request_and_validate(event_text, event_instant):
    before = datetime.now(timezone.utc)
    try:
        response = requests.post(
            URL,
            headers=AUTH_HEADERS,
            json={"event_time": event_text},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    after = datetime.now(timezone.utc)

    assert response.status_code == 200, \
        f"Expected status code 200 for {event_text}, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert "sla" in data, f"Response JSON missing 'sla' key. Response: {data}"
    assert isinstance(data["sla"], (int, float)), f"'sla' value is not a number. Response: {data}"
    assert not isinstance(data["sla"], bool), f"'sla' must be a calculated number, not a boolean. Response: {data}"
    assert data.get("status") == "ok", f"Expected status 'ok', but got {data.get('status')}."

    value = float(data["sla"])
    assert math.isfinite(value) and value >= 0, f"SLA must be finite and non-negative, got {value}."

    # The repository's SLA definition is sqrt(abs(now_utc - event_utc)).
    # Squaring the response permits an exact time-delta check bounded by the
    # timestamps immediately before and after the request.
    observed_seconds = value * value
    distances = [
        abs((before - event_instant).total_seconds()),
        abs((after - event_instant).total_seconds()),
    ]
    lower = max(0.0, min(distances) - 1.0)
    upper = max(distances) + 1.0
    assert lower <= observed_seconds <= upper, \
        (f"Incorrect SLA for {event_text}: sla^2={observed_seconds}, "
         f"expected elapsed UTC seconds in [{lower}, {upper}].")
    return value


def test_http_service_success():
    event = datetime(2023, 10, 27, 15, 30, 0, tzinfo=timezone.utc)
    _request_and_validate("2023-10-27T15:30:00Z", event)


def test_timezone_normalization_and_log_correlation():
    # These are the timestamps present in service_a.log and service_b.log.
    # They denote the same instant despite using different timezone notation.
    event = datetime(2023, 10, 27, 15, 30, 0, tzinfo=timezone.utc)
    z_value = _request_and_validate("2023-10-27T15:30:00Z", event)
    offset_value = _request_and_validate("2023-10-27T11:30:00-04:00", event)
    assert abs((z_value * z_value) - (offset_value * offset_value)) < 5.0, \
        "Equivalent timestamps from the two service logs were not correlated to the same UTC instant."


def test_sla_uses_event_time_for_varied_offsets():
    now = datetime.now(timezone.utc)
    past = now - timedelta(hours=3, minutes=17)
    future = now + timedelta(days=2, minutes=11)

    plus_0530 = timezone(timedelta(hours=5, minutes=30))
    minus_0700 = timezone(timedelta(hours=-7))
    past_text = past.astimezone(plus_0530).isoformat(timespec="microseconds")
    future_text = future.astimezone(minus_0700).isoformat(timespec="microseconds")

    past_value = _request_and_validate(past_text, past)
    future_value = _request_and_validate(future_text, future)
    assert abs((past_value * past_value) - (future_value * future_value)) > 1000, \
        "Different event times produced effectively constant SLA results."


def test_http_service_unauthorized():
    payload = {"event_time": "2023-10-27T15:30:00Z"}
    try:
        response = requests.post(URL, headers={"Content-Type": "application/json"}, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    assert response.status_code in (401, 403), \
        f"Expected status code 401 or 403 for unauthorized request, but got {response.status_code}."

    wrong = {"Authorization": "Bearer wrong-token", "Content-Type": "application/json"}
    response = requests.post(URL, headers=wrong, json=payload, timeout=5)
    assert response.status_code in (401, 403), \
        f"Expected status code 401 or 403 for an invalid token, but got {response.status_code}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
