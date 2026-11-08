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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import signal
import stat
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/metrics"
AUTH_HEADER = {"Authorization": "Bearer DataFlow2024"}
ARCHIVE_PATH = "/home/user/rolling_archive.jsonl"
CONTROL_PROC = None
EXPECTED = None
CRON_COMMAND = None


def request_metrics(headers=None, timeout=5):
    return requests.get(URL, headers=headers, timeout=timeout)


def listening_socket():
    wanted_port = 8080
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        for line in list(f)[1:]:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if int(port_hex, 16) == wanted_port and fields[3] == "0A":
                return address, fields[9]
    return None, None


def pid_for_socket_inode(inode):
    target = f"socket:[{inode}]"
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == target:
                        return int(name)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def read_nul_file(path):
    with open(path, "rb") as f:
        return [x.decode("utf-8", "surrogateescape") for x in f.read().split(b"\0") if x]


def active_stream_generator():
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{name}/exe")
            argv = read_nul_file(f"/proc/{name}/cmdline")
        except OSError:
            continue
        if exe == "/app/stream_gen" and argv == ["/app/stream_gen", "--start-stream-0x4A"]:
            return int(name)
    return None


def process_environment(pid):
    env = os.environ.copy()
    try:
        for item in read_nul_file(f"/proc/{pid}/environ"):
            if "=" in item:
                key, value = item.split("=", 1)
                env[key] = value
    except OSError:
        pass
    return env


def submission_artifact(argv, cwd):
    interpreter_names = {
        "python", "python3", "python3.11", "node", "bash", "sh", "dash",
        "perl", "ruby", "php"
    }
    for index, arg in enumerate(argv):
        if arg.startswith("-"):
            continue
        path = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        path = os.path.realpath(path)
        try:
            mode = os.stat(path).st_mode
        except OSError:
            continue
        if not stat.S_ISREG(mode) or path == "/app/stream_gen":
            continue
        if index == 0 and os.path.basename(path) in interpreter_names:
            continue
        return path
    return None


def wait_for_metrics(expected, timeout=10):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            response = request_metrics(AUTH_HEADER, timeout=1)
            if response.status_code == 200:
                last = response.json()
                if isinstance(last, dict) and set(last) == set(expected):
                    if all(
                        isinstance(last[k], (int, float))
                        and not isinstance(last[k], bool)
                        and math.isclose(float(last[k]), expected[k], rel_tol=1e-7, abs_tol=1e-7)
                        for k in expected
                    ):
                        return last
        except (requests.RequestException, ValueError):
            pass
        time.sleep(0.2)
    pytest.fail(f"Controlled stream did not produce the expected rolling averages; last response was {last!r}")


def cron_daemon_running():
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            exe = os.path.basename(os.path.realpath(f"/proc/{name}/exe"))
            argv = read_nul_file(f"/proc/{name}/cmdline")
        except OSError:
            continue
        if exe in {"cron", "crond"} and argv:
            return True
    return False


def test_api_unauthorized():
    try:
        response = request_metrics()
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {URL}: {e}")
    assert response.status_code == 401, f"Expected status code 401 for unauthorized access, got {response.status_code}"

    response = request_metrics({"Authorization": "Bearer wrong-token"})
    assert response.status_code == 401, "An incorrect bearer token must also be rejected"


def test_api_authorized():
    try:
        response = request_metrics(AUTH_HEADER)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {URL}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert isinstance(data, dict), "Expected JSON response to be a dictionary"
    for key, value in data.items():
        assert isinstance(key, str), f"Expected key {key} to be a string"
        assert isinstance(value, (int, float)), f"Expected value for {key} to be a number, got {type(value)}"

    address, inode = listening_socket()
    assert inode is not None, "No IPv4 listener was found on port 8080"
    assert address == "0100007F", "The service must bind exactly to 127.0.0.1, not a wildcard address"


def test_crontab_configured():
    global CRON_COMMAND
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it configured?")

    assert "rolling_archive.jsonl" in content, "Crontab does not contain a job writing to rolling_archive.jsonl"
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"] and "rolling_archive.jsonl" in fields[5]:
            CRON_COMMAND = fields[5]
            break
    assert CRON_COMMAND is not None, "No every-minute cron job targeting rolling_archive.jsonl was found"


def test_stream_and_rolling_behavior():
    global CONTROL_PROC, EXPECTED

    assert active_stream_generator() is not None, "/app/stream_gen is not running with the discovered activation flag"

    address, inode = listening_socket()
    assert inode is not None
    pid = pid_for_socket_inode(inode)
    assert pid not in (None, 1), "Could not identify the submitted API process"

    try:
        argv = read_nul_file(f"/proc/{pid}/cmdline")
        cwd = os.readlink(f"/proc/{pid}/cwd")
        env = process_environment(pid)
    except OSError as e:
        pytest.fail(f"Could not inspect the submitted API process: {e}")

    assert argv, "The API process has no executable command line"
    artifact = submission_artifact(argv, cwd)
    assert artifact is not None, "The listener is not backed by an identifiable submitted script or executable"

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline:
        _, old_inode = listening_socket()
        if old_inode is None:
            break
        time.sleep(0.1)
    else:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        time.sleep(0.5)
    assert listening_socket()[1] is None, "The original API process could not be stopped for controlled testing"

    CONTROL_PROC = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    base = int(time.time()) - random.randint(700, 1400)
    a1, a2 = random.sample(range(110, 900), 2)
    b1, b2 = random.sample(range(110, 900), 2)
    old1, old2 = random.sample(range(10, 100), 2)
    records = [
        (base, "正常", old1 / 10.0),
        (base + 20, "ошибка", old2 / 10.0),
        (base + 40, "正常", a1 / 10.0),
        (base + 50, "ошибка", b1 / 10.0),
        (base + 80, "正常", a2 / 10.0),
        (base + 101, "ошибка", b2 / 10.0),
    ]
    payload = "".join(f"{ts}|{tag}|{value:.1f}\n" for ts, tag, value in records).encode("utf-8")
    try:
        CONTROL_PROC.stdin.write(payload)
        CONTROL_PROC.stdin.flush()
    except (BrokenPipeError, OSError) as e:
        pytest.fail(f"Submitted processor would not consume a controlled stdin stream: {e}")

    # At timestamp base+101, only records newer than base+41 are in the trailing
    # 60 seconds. This deliberately excludes the old records and the base+40 record.
    EXPECTED = {
        "正常": a2 / 10.0,
        "ошибка": (b1 + b2) / 20.0,
    }
    wait_for_metrics(EXPECTED)


def test_rolling_archive_populated():
    assert EXPECTED is not None, "Controlled API test did not run"
    assert cron_daemon_running(), "A cron job was installed, but no cron daemon is running"

    os.makedirs(os.path.dirname(ARCHIVE_PATH), exist_ok=True)
    with open(ARCHIVE_PATH, "w", encoding="utf-8"):
        pass

    timeout = 75
    deadline = time.time() + timeout
    lines = []
    while time.time() < deadline:
        try:
            with open(ARCHIVE_PATH, "r", encoding="utf-8") as f:
                lines = [line.strip() for line in f if line.strip()]
        except FileNotFoundError:
            lines = []
        if lines:
            break
        time.sleep(1)

    assert os.path.exists(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} was not created within {timeout} seconds"
    assert os.path.getsize(ARCHIVE_PATH) > 0, f"Archive file {ARCHIVE_PATH} is empty"
    assert lines, "The installed every-minute cron job did not append an archive line"

    try:
        data = json.loads(lines[-1])
    except ValueError:
        pytest.fail(f"Last line in archive file is not valid JSON: {lines[-1]}")
    assert isinstance(data, dict), "Expected JSON line to be a dictionary"
    assert set(data) == set(EXPECTED), f"Archived JSON is not the authenticated API response: {data!r}"
    for key, expected in EXPECTED.items():
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool)
        assert math.isclose(float(data[key]), expected, rel_tol=1e-7, abs_tol=1e-7), \
            f"Archived value for {key} does not match the live rolling metric"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
