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
import array
import json
import math
import os
import random
import re
import socket
import subprocess
import threading
import time
import wave

import pytest
import requests

APP_DIR = "/home/user/telemetry_app"
SERVER_PATH = APP_DIR + "/server.py"
HEALTH_PATH = APP_DIR + "/health_check.exp"
HOST = "127.0.0.1"
HTTP_PORT = 9080
TCP_PORT = 9081
STATE = {"proc": None}


def decode_dtmf_pin(path):
    with wave.open(path, "rb") as wav_file:
        assert wav_file.getnchannels() == 1, "DTMF audio must be mono."
        rate = wav_file.getframerate()
        width = wav_file.getsampwidth()
        assert width == 2, "Unexpected DTMF sample width."
        samples = array.array("h", wav_file.readframes(wav_file.getnframes()))
        if os.sys.byteorder != "little":
            samples.byteswap()

    active = [abs(x) > 500 for x in samples]
    regions = []
    start = None
    for i, is_active in enumerate(active):
        if is_active and start is None:
            start = i
        elif not is_active and start is not None:
            if i - start >= int(rate * 0.1):
                regions.append((start, i))
            start = None
    if start is not None and len(samples) - start >= int(rate * 0.1):
        regions.append((start, len(samples)))

    rows = [697, 770, 852, 941]
    cols = [1209, 1336, 1477]
    keypad = {
        (697, 1209): "1", (697, 1336): "2", (697, 1477): "3",
        (770, 1209): "4", (770, 1336): "5", (770, 1477): "6",
        (852, 1209): "7", (852, 1336): "8", (852, 1477): "9",
        (941, 1209): "*", (941, 1336): "0", (941, 1477): "#",
    }

    def power(data, freq):
        coeff = 2.0 * math.cos(2.0 * math.pi * freq / rate)
        q0 = q1 = q2 = 0.0
        for sample in data:
            q0 = coeff * q1 - q2 + sample
            q2, q1 = q1, q0
        return q1 * q1 + q2 * q2 - coeff * q1 * q2

    digits = []
    for begin, end in regions:
        data = samples[begin:end]
        row = max(rows, key=lambda f: power(data, f))
        col = max(cols, key=lambda f: power(data, f))
        digits.append(keypad[(row, col)])
    return "".join(digits)


PIN = decode_dtmf_pin("/app/telemetry.wav")
assert PIN == "4092", f"Unexpected PIN decoded from telemetry.wav: {PIN!r}"


def _listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        state = fields[3]
                        if local_port == port and state == "0A":
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def _kill_port_listeners(*ports):
    inodes = set()
    for port in ports:
        inodes.update(_listening_inodes(port))
    if not inodes:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), 15)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if not any(_listening_inodes(port) for port in ports):
            return
        time.sleep(0.05)
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        try:
            links = [os.readlink(f"/proc/{pid}/fd/{fd}") for fd in os.listdir(f"/proc/{pid}/fd")]
        except (FileNotFoundError, PermissionError, OSError):
            continue
        if any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            try:
                os.kill(int(pid), 9)
            except (ProcessLookupError, PermissionError):
                pass


def _wait_for_ports(proc, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"server.py exited early with status {proc.returncode}")
        if _listening_inodes(HTTP_PORT) and _listening_inodes(TCP_PORT):
            return
        time.sleep(0.05)
    pytest.fail("server.py did not listen on both required ports")


def _start_submitted_server():
    proc = subprocess.Popen(
        ["python3", SERVER_PATH],
        cwd=APP_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    _wait_for_ports(proc)
    STATE["proc"] = proc
    return proc


def _stop_servers():
    proc = STATE.get("proc")
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    STATE["proc"] = None
    _kill_port_listeners(HTTP_PORT, TCP_PORT)


def _tcp_exchange(value):
    with socket.create_connection((HOST, TCP_PORT), timeout=2) as s:
        s.settimeout(2)
        s.sendall(value.encode("utf-8") + b"\n")
        chunks = []
        while True:
            part = s.recv(1024)
            if not part:
                break
            chunks.append(part)
        return b"".join(chunks).decode("utf-8")


def _assert_http_service():
    url = "http://127.0.0.1:9080/status.json"
    try:
        response = requests.get(url, timeout=2)
        assert response.status_code == 200, f"HTTP GET {url} returned status {response.status_code}."
        data = response.json()
        assert data == {"status": "provisioned"}, f"HTTP response JSON is incorrect: {data}"
    except requests.RequestException as e:
        assert False, f"HTTP service check failed: {e}"


def _assert_tcp_service():
    response = _tcp_exchange("4092")
    assert response == "AUTH_OK\n", f"Expected 'AUTH_OK\\n' for valid PIN, got {response!r}"

    response = _tcp_exchange("9999")
    assert response == "AUTH_FAIL\n", f"Expected 'AUTH_FAIL\\n' for invalid PIN, got {response!r}"

    for valid_variant in (f"  {PIN}", f"{PIN}  ", f"\t{PIN}\t"):
        assert _tcp_exchange(valid_variant) == "AUTH_OK\n"

    invalid_values = ["", PIN[:-1], PIN + "0", "x" + PIN, PIN + "x", "0000", "1234"]
    invalid_values.extend(
        str(random.SystemRandom().randrange(100000, 999999999)) for _ in range(20)
    )
    for value in invalid_values:
        assert value.strip() != PIN
        response = _tcp_exchange(value)
        assert response == "AUTH_FAIL\n", f"Invalid value {value!r} was not rejected: {response!r}"


def test_directory_structure_and_symlink():
    v1_dir = "/home/user/telemetry_app/releases/v1"
    logs_dir = "/home/user/telemetry_app/logs"
    current_symlink = "/home/user/telemetry_app/current"

    assert os.path.isdir(v1_dir), f"Directory {v1_dir} is missing or not a directory."
    assert os.path.isdir(logs_dir), f"Directory {logs_dir} is missing or not a directory."
    assert os.path.islink(current_symlink), f"{current_symlink} is not a symlink."
    target = os.readlink(current_symlink)
    assert os.path.abspath(os.path.join(APP_DIR, target)) == os.path.abspath(v1_dir), \
        f"Symlink {current_symlink} does not point to {v1_dir}."


def test_status_json():
    status_file = "/home/user/telemetry_app/releases/v1/status.json"
    assert os.path.isfile(status_file), f"File {status_file} is missing."
    with open(status_file, "r") as f:
        content = f.read().strip()
    try:
        data = json.loads(content)
        assert data == {"status": "provisioned"}, f"status.json content is incorrect: {data}"
    except json.JSONDecodeError:
        assert False, f"status.json does not contain valid JSON: {content}"


def test_server_script_exists():
    assert os.path.isfile(SERVER_PATH), f"Required server implementation missing at {SERVER_PATH}."
    assert not os.path.islink(SERVER_PATH), "server.py must be the submitted Python file, not a symlink."


def test_http_service():
    _assert_http_service()


def test_tcp_auth_service():
    _assert_tcp_service()


def test_submitted_server_script_runs_both_services():
    _stop_servers()
    proc = _start_submitted_server()
    assert proc.poll() is None
    _assert_http_service()
    _assert_tcp_service()


def _run_fake_auth(response, received):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((HOST, TCP_PORT))
    listener.listen(1)

    def serve():
        try:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(3)
                data = b""
                while b"\n" not in data:
                    part = conn.recv(1024)
                    if not part:
                        break
                    data += part
                received.append(data.decode("utf-8", errors="replace"))
                conn.sendall(response)
        finally:
            listener.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return thread


def test_expect_script():
    assert os.path.isfile(HEALTH_PATH), f"Expect script missing at {HEALTH_PATH}."
    assert os.access(HEALTH_PATH, os.X_OK), "health_check.exp is not executable by cron."
    with open(HEALTH_PATH, "r") as f:
        content = f.read()

    assert "4092" in content, "Expect script does not contain the extracted PIN '4092'."
    assert "AUTH_OK" in content, "Expect script does not contain the expected 'AUTH_OK' string."
    assert re.search(r"\bspawn\b[^\n]*(?:\bnc\b|netcat)[^\n]*127\.0\.0\.1[^\n]*9081", content), \
        "Expect script does not spawn nc to the TCP auth service."

    _stop_servers()
    success_received = []
    fail_received = []
    try:
        thread = _run_fake_auth(b"AUTH_OK\n", success_received)
        success = subprocess.run(["expect", HEALTH_PATH], capture_output=True, text=True, timeout=15)
        thread.join(timeout=3)

        thread = _run_fake_auth(b"AUTH_FAIL\n", fail_received)
        failure = subprocess.run(["expect", HEALTH_PATH], capture_output=True, text=True, timeout=15)
        thread.join(timeout=3)
    finally:
        _kill_port_listeners(TCP_PORT)
        _start_submitted_server()

    assert success.returncode == 0, f"Health check failed against AUTH_OK service: {success.stdout}{success.stderr}"
    assert success_received and success_received[0].strip() == PIN, \
        f"Health check sent the wrong PIN: {success_received!r}"
    assert failure.returncode == 1, \
        f"Health check must exit 1 when AUTH_OK is not received; got {failure.returncode}."
    assert fail_received and fail_received[0].strip() == PIN


def _minute_set(expr):
    values = set()
    for part in expr.split(","):
        if part == "*":
            values.update(range(60))
        elif re.fullmatch(r"\*/\d+", part):
            step = int(part[2:])
            values.update(range(0, 60, step))
        elif re.fullmatch(r"\d+-\d+/\d+", part):
            bounds, step = part.split("/")
            begin, end = map(int, bounds.split("-"))
            values.update(range(begin, end + 1, int(step)))
        elif part.isdigit():
            values.add(int(part))
        else:
            return None
    return values


def test_cron_job():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        assert False, "Failed to read crontab. No crontab for user?"

    assert "*/5" in crontab_output or "0,5,10" in crontab_output or "5 * * * *" in crontab_output, \
        "Crontab does not seem to run every 5 minutes."
    assert HEALTH_PATH in crontab_output, "Crontab does not execute health_check.exp."
    assert APP_DIR + "/logs/health.log" in crontab_output, "Crontab does not redirect to health.log."

    expected_minutes = set(range(0, 60, 5))
    matching = []
    for raw_line in crontab_output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("@"):
            continue
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        minute, hour, dom, month, dow, command = fields
        if HEALTH_PATH not in command:
            continue
        if _minute_set(minute) != expected_minutes or [hour, dom, month, dow] != ["*", "*", "*", "*"]:
            continue
        log = re.escape(APP_DIR + "/logs/health.log")
        stdout_redirect = re.search(rf"(?:^|\s)(?:>|>>)\s*{log}(?:\s|$)", command)
        stderr_redirect = re.search(r"(?:^|\s)2>&1(?:\s|$)", command)
        if stdout_redirect and stderr_redirect:
            matching.append(line)
    assert matching, "No cron entry runs health_check.exp every five minutes with both outputs redirected to health.log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
