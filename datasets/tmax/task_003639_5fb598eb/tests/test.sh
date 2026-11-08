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
import json
import os
import random
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

PID_FILE = "/home/user/server.pid"
BASE_URL = "http://127.0.0.1:8080"


def read_pid():
    assert os.path.isfile(PID_FILE), f"Missing PID file: {PID_FILE}"
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)
    assert os.path.isdir(f"/proc/{pid}"), f"PID {pid} is not running"
    return pid


def pid_owns_listener(pid):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    local = fields[1]
                    if table.endswith("tcp"):
                        if local.upper() == "0100007F:1F90":
                            inodes.add(fields[9])
                    else:
                        # IPv4-mapped or native IPv6 is not accepted: the task requires 127.0.0.1.
                        pass
        except FileNotFoundError:
            pass

    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                link = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if link.startswith("socket:[") and link[8:-1] in inodes:
                return True
    except FileNotFoundError:
        return False
    return False


def assert_json_response(path, expected):
    url = BASE_URL + path
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API server at {url}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("application/json"), \
        f"Expected JSON Content-Type, got {response.headers.get('Content-Type')}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data == expected, f"Expected {expected}, got {data}"


def wait_for_restarted_server(timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            pid = read_pid()
            if pid_owns_listener(pid):
                requests.get(BASE_URL + "/solve?target=1&w=1", timeout=0.5)
                return pid
        except Exception as e:
            last_error = e
        time.sleep(0.1)
    pytest.fail(f"Restarted server did not become ready: {last_error}")


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline and os.path.isdir(f"/proc/{pid}"):
        time.sleep(0.05)
    if os.path.isdir(f"/proc/{pid}"):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_complete_api_implementation():
    # Preserve the original PID-file assertion and strengthen it to require that
    # the recorded process owns the required listening socket.
    original_pid = read_pid()
    assert pid_owns_listener(original_pid), \
        f"PID {original_pid} does not own a listener on exactly 127.0.0.1:8080"

    # Preserve both original fixed behavioral assertions.
    assert_json_response(
        "/solve?target=100&w=10,15,25",
        {"status": "success", "result": 50},
    )
    assert_json_response(
        "/solve?target=10&w=2,3",
        {"status": "success", "result": 5},
    )

    # The running process must actually have loaded both the requested solver and
    # its formerly missing dependency.
    with open(f"/proc/{original_pid}/maps", "r") as f:
        maps = f.read()
    assert "/app/libsolver.so" in maps, "Server process has not loaded /app/libsolver.so"
    assert "/app/legacy_libs/libhelpers.so.1" in maps, \
        "Server process has not resolved and loaded libhelpers.so.1"

    with open(f"/proc/{original_pid}/cmdline", "rb") as f:
        command = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert command, "Could not determine the server command"
    cwd = os.readlink(f"/proc/{original_pid}/cwd")
    with open(f"/proc/{original_pid}/environ", "rb") as f:
        env_entries = [x for x in f.read().split(b"\0") if x]
    env = os.environ.copy()
    for entry in env_entries:
        key, sep, value = entry.partition(b"=")
        if sep:
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")

    tempdir = tempfile.mkdtemp(prefix="verifier-instrument-")
    parser_backup = os.path.join(tempdir, "oracle_parser.original")
    solver_backup = os.path.join(tempdir, "libsolver.original.so")
    parser_test = os.path.join(tempdir, "oracle_parser.test")
    solver_test = os.path.join(tempdir, "libsolver.test.so")
    call_log = os.path.join(tempdir, "parser_calls.jsonl")
    shutil.copy2("/app/oracle_parser", parser_backup)
    shutil.copy2("/app/libsolver.so", solver_backup)

    # Per-verification secrets make hardcoded responses and direct subtraction
    # insufficient. The replacement parser derives nontrivial data from the exact
    # raw path, while the replacement run_solver uses a different formula.
    secret_t = random.SystemRandom().randint(200, 700)
    secret_w1 = random.SystemRandom().randint(20, 80)
    secret_w2 = random.SystemRandom().randint(80, 150)
    coef = random.SystemRandom().randint(3, 9)
    count_coef = random.SystemRandom().randint(11, 31)

    parser_source = f'''#!/usr/bin/python3
import json, sys
if len(sys.argv) != 2:
    raise SystemExit(1)
raw = sys.argv[1]
with open({call_log!r}, "a") as log:
    log.write(json.dumps(raw) + "\\n")
h = sum((i + 1) * ord(ch) for i, ch in enumerate(raw)) % 997
payload = {{
    "target": {secret_t} + h,
    "weights": [len(raw) + {secret_w1}, raw.count(",") + {secret_w2}, sum(raw.encode()) % 101, -7],
}}
print(json.dumps(payload))
'''
    with open(parser_test, "w") as f:
        f.write(parser_source)
    os.chmod(parser_test, 0o755)

    c_source = os.path.join(tempdir, "solver_test.c")
    with open(c_source, "w") as f:
        f.write(f'''int run_solver(int target, int *weights, int count) {{
    int result = target * {coef} + count * {count_coef};
    for (int i = 0; i < count; ++i) result += weights[i] * (i + 3);
    return result;
}}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", solver_test, c_source],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    restarted = None
    restarted_pid = None
    try:
        stop_pid(original_pid)
        shutil.copy2(parser_test, "/app/oracle_parser")
        shutil.copy2(solver_test, "/app/libsolver.so")
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass

        restarted = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        restarted_pid = wait_for_restarted_server()

        tested_paths = []
        for _ in range(4):
            target = random.SystemRandom().randint(-500, 1500)
            weights = [random.SystemRandom().randint(-90, 160) for _ in range(random.randint(1, 6))]
            nonce = uuid.uuid4().hex
            raw_path = f"/solve?target={target}&w={','.join(map(str, weights))}&nonce={nonce}"
            tested_paths.append(raw_path)

            h = sum((i + 1) * ord(ch) for i, ch in enumerate(raw_path)) % 997
            parsed_target = secret_t + h
            parsed_weights = [
                len(raw_path) + secret_w1,
                raw_path.count(",") + secret_w2,
                sum(raw_path.encode()) % 101,
                -7,
            ]
            expected_result = parsed_target * coef + len(parsed_weights) * count_coef
            expected_result += sum(value * (i + 3) for i, value in enumerate(parsed_weights))
            assert_json_response(
                raw_path,
                {"status": "success", "result": expected_result},
            )

        with open(call_log, "r") as f:
            observed_calls = [json.loads(line) for line in f if line.strip()]
        for raw_path in tested_paths:
            assert raw_path in observed_calls, \
                f"/app/oracle_parser was not invoked with the exact raw path {raw_path!r}"

        with open(f"/proc/{restarted_pid}/maps", "r") as f:
            restarted_maps = f.read()
        assert "/app/libsolver.so" in restarted_maps, \
            "Restarted server did not load the instrumented /app/libsolver.so"
    finally:
        if restarted_pid is not None:
            stop_pid(restarted_pid)
        if restarted is not None:
            try:
                os.killpg(restarted.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        shutil.copy2(parser_backup, "/app/oracle_parser")
        shutil.copy2(solver_backup, "/app/libsolver.so")
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
