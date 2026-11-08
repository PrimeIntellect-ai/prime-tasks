#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.client
import json
import os
import random
import signal
import socket
import subprocess
import time

import pytest

APP_DIR = "/app/math-daemon"
BINARY = os.path.join(APP_DIR, "target", "release", "math-daemon")
PORT = 9000
SERVICE_PROCESS = None


def container_ip():
    candidates = []
    try:
        candidates.extend(socket.gethostbyname_ex(socket.gethostname())[2])
    except OSError:
        pass
    try:
        output = subprocess.check_output(["hostname", "-I"], text=True)
        candidates.extend(output.split())
    except (OSError, subprocess.SubprocessError):
        pass
    for address in candidates:
        if ":" not in address and not address.startswith("127.") and address != "0.0.0.0":
            return address
    pytest.fail("Could not determine a non-loopback container IPv4 address")


def listener_inodes(wildcard_only=False):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    local_address, state = fields[1], fields[3]
                    address_hex, port_hex = local_address.rsplit(":", 1)
                    if int(port_hex, 16) != PORT or state != "0A":
                        continue
                    if wildcard_only:
                        expected = "0" * (8 if table.endswith("tcp") else 32)
                        if address_hex != expected:
                            continue
                    found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def assert_ipv4_wildcard_listener():
    with open("/proc/net/tcp") as handle:
        next(handle, None)
        for line in handle:
            fields = line.split()
            address_hex, port_hex = fields[1].rsplit(":", 1)
            if int(port_hex, 16) == PORT and fields[3] == "0A" and address_hex == "00000000":
                return
    pytest.fail("No service is listening on required address 0.0.0.0:9000")


def pids_for_inodes(inodes):
    pids = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(os.path.basename(proc_dir))
            for fd in glob.glob(os.path.join(proc_dir, "fd", "*")):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(pid)
        except (OSError, ValueError):
            continue
    return pids


def stop_port_listeners():
    pids = pids_for_inodes(listener_inodes())
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_inodes():
        time.sleep(0.1)
    for pid in pids_for_inodes(listener_inodes()):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_inodes():
        time.sleep(0.1)
    assert not listener_inodes(), "Could not stop the existing port 9000 listener"


def wait_for_service(process, host):
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Compiled daemon exited early with status {process.returncode}")
        try:
            with socket.create_connection((host, PORT), timeout=0.5):
                return
        except OSError as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Compiled daemon did not become reachable at {host}:{PORT}: {last_error}")


def post_eval(host, bytecode):
    connection = http.client.HTTPConnection(host, PORT, timeout=5)
    try:
        body = json.dumps({"bytecode": bytecode})
        connection.request("POST", "/eval", body=body, headers={"Content-Type": "application/json"})
        response = connection.getresponse()
        raw = response.read()
        try:
            data = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            pytest.fail(f"Service returned invalid JSON (HTTP {response.status}): {raw!r}: {exc}")
        return response.status, data
    except OSError as exc:
        pytest.fail(f"Failed to connect to the service: {exc}")
    finally:
        connection.close()


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_submitted_daemon():
    global SERVICE_PROCESS
    assert os.path.isdir(APP_DIR), f"Directory {APP_DIR} does not exist."

    # The agent was required to leave an externally reachable service running.
    assert_ipv4_wildcard_listener()
    external_host = container_ip()
    try:
        with socket.create_connection((external_host, PORT), timeout=5):
            pass
    except OSError as exc:
        pytest.fail(f"Running service is not reachable through the container interface: {exc}")

    # Do not trust a pre-existing process or stale binary: compile and execute the submitted app.
    stop_port_listeners()
    try:
        build = subprocess.run(
            ["cargo", "build", "--release"],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("cargo build --release timed out after 120 seconds")
    assert build.returncode == 0, f"cargo build --release failed:\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"
    assert os.path.isfile(BINARY), f"Expected compiled daemon at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled daemon is not executable: {BINARY}"
    with open(BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Compiled daemon is not an ELF executable"

    log = open("/tmp/math-daemon-verifier.log", "wb")
    SERVICE_PROCESS = subprocess.Popen(
        [BINARY], cwd=APP_DIR, stdout=log, stderr=subprocess.STDOUT, start_new_session=True
    )
    wait_for_service(SERVICE_PROCESS, external_host)
    assert_ipv4_wildcard_listener()
    yield external_host


def test_cargo_test_passes():
    """Verify that cargo test passes cleanly in /app/math-daemon."""
    assert os.path.isdir(APP_DIR), f"Directory {APP_DIR} does not exist."
    try:
        result = subprocess.run(
            ["cargo", "test"],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"cargo test failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    except subprocess.TimeoutExpired:
        pytest.fail("cargo test timed out after 60 seconds.")


def test_service_eval_valid(rebuild_and_run_submitted_daemon):
    host = rebuild_and_run_submitted_daemon
    status, data = post_eval(host, [1, 20, 1, 4, 4])
    assert 200 <= status < 300, f"Expected successful HTTP status, got {status}"
    assert data.get("result") == 5, f"Expected result 5, got {data.get('result')}"
    assert data.get("error") is None, f"Expected error to be null, got {data.get('error')}"


def test_service_eval_division_by_zero(rebuild_and_run_submitted_daemon):
    host = rebuild_and_run_submitted_daemon
    _, data = post_eval(host, [1, 10, 1, 0, 4])
    assert data.get("result") is None, f"Expected result to be null, got {data.get('result')}"
    assert data.get("error") == "DivisionByZero", f"Expected error 'DivisionByZero', got {data.get('error')}"


def make_expression(rng, depth):
    if depth <= 0 or rng.random() < 0.3:
        value = rng.randrange(256)
        return [1, value], value
    left_code, left_value = make_expression(rng, depth - 1)
    for _ in range(100):
        right_code, right_value = make_expression(rng, depth - 1)
        if right_value != 0:
            return left_code + right_code + [4], left_value // right_value
    return left_code + [1, 1, 4], left_value


def test_randomized_interpreter_behavior(rebuild_and_run_submitted_daemon):
    host = rebuild_and_run_submitted_daemon
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    # Inputs and expected values are generated by the verifier, preventing a fixed response table.
    for _ in range(64):
        left_code, left_value = make_expression(rng, rng.randint(1, 4))
        right_code, right_value = make_expression(rng, rng.randint(1, 4))
        while right_value == 0:
            right_code, right_value = make_expression(rng, rng.randint(1, 4))
        bytecode = left_code + right_code + [4]
        expected = left_value // right_value
        status, data = post_eval(host, bytecode)
        assert 200 <= status < 300, f"Expected successful HTTP status, got {status}"
        assert data.get("result") == expected, (
            f"For bytecode {bytecode}, expected {expected}, got {data.get('result')}"
        )
        assert data.get("error") is None, f"Unexpected error for {bytecode}: {data.get('error')}"


def test_randomized_division_by_zero(rebuild_and_run_submitted_daemon):
    host = rebuild_and_run_submitted_daemon
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    # The divisor is a randomly generated expression n/d whose value is zero.
    for _ in range(32):
        numerator_code, _ = make_expression(rng, rng.randint(1, 3))
        n = rng.randrange(0, 255)
        d = rng.randrange(n + 1, 256)
        bytecode = numerator_code + [1, n, 1, d, 4, 4]
        _, data = post_eval(host, bytecode)
        assert data.get("result") is None, f"Expected null result for {bytecode}, got {data.get('result')}"
        assert data.get("error") == "DivisionByZero", (
            f"Expected DivisionByZero for {bytecode}, got {data.get('error')}"
        )
        assert SERVICE_PROCESS.poll() is None, "Daemon crashed while handling division by zero"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
