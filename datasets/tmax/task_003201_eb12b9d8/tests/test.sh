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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import socket
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
SOURCE = "/home/user/dashboard/server.c"
BINARY = "/home/user/dashboard/server"
AUTH = {"Authorization": "Bearer mobile_ci_secret"}


def test_compiled_artifacts_exist():
    assert os.path.isfile(SOURCE), f"Missing {SOURCE}"
    assert os.path.isfile(BINARY), f"Missing compiled server {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Server is not executable: {BINARY}"


def test_health_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=2)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Expected JSON response, got: {response.text}")
        assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /health: {e}")


def test_score_endpoint_auth_missing():
    try:
        response = requests.post(f"{BASE_URL}/score", json={"crash_count": 7}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Server did not return an HTTP rejection for missing authorization: {e}")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 without authorization, got {response.status_code}"
    )
    try:
        data = response.json()
        assert "final_score" not in data, "Server returned final_score without auth header"
    except ValueError:
        pass

    response = requests.post(
        f"{BASE_URL}/score",
        json={"crash_count": 7},
        headers={"Authorization": "Bearer wrong_secret"},
        timeout=2,
    )
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for invalid authorization, got {response.status_code}"
    )


def test_score_endpoint_success():
    try:
        response = requests.post(
            f"{BASE_URL}/score", json={"crash_count": 7}, headers=AUTH, timeout=2
        )
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Expected JSON response, got: {response.text}")
        assert data.get("final_score") == 1540, f"Expected {{'final_score': 1540}}, got {data}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /score: {e}")


def test_score_endpoint_multiple_runtime_inputs():
    counts = [0, 1, 2, 13, secrets.randbelow(1000) + 20, secrets.randbelow(10000) + 2000]
    for count in counts:
        response = requests.post(
            f"{BASE_URL}/score",
            json={"crash_count": count},
            headers=AUTH,
            timeout=2,
        )
        assert response.status_code == 200, (
            f"Expected 200 for crash_count={count}, got {response.status_code}"
        )
        assert response.json().get("final_score") == 220 * count, (
            f"Incorrect score for crash_count={count}: {response.text}"
        )


def test_calculate_optimal_score_dynamic_programming():
    wrapper = "/tmp/knapsack_wrapper.c"
    library = "/tmp/knapsack_wrapper.so"
    with open(wrapper, "w") as f:
        f.write(r'''
#define main submitted_dashboard_main
#include "/home/user/dashboard/server.c"
#undef main
int verifier_calculate(int capacity_arg, int *weights_arg, int *values_arg, int n_arg) {
    return calculate_optimal_score(capacity_arg, weights_arg, values_arg, n_arg);
}
''')
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O0", "-g", "-o", library, wrapper],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"Could not compile server.c for algorithm testing:\n{result.stderr}"

    lib = ctypes.CDLL(library)
    fn = lib.verifier_calculate
    fn.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.c_int]
    fn.restype = ctypes.c_int

    def expected(capacity, weights, values):
        dp = [0] * (capacity + 1)
        for weight, value in zip(weights, values):
            for c in range(capacity, weight - 1, -1):
                dp[c] = max(dp[c], dp[c - weight] + value)
        return dp[capacity]

    cases = [
        (50, [10, 20, 30], [60, 100, 120]),
        (10, [6, 5, 5], [12, 10, 10]),
        (7, [8, 3, 4, 5], [100, 4, 5, 7]),
        (0, [1, 2, 3], [5, 6, 7]),
    ]
    for _ in range(20):
        n = secrets.randbelow(8) + 2
        capacity = secrets.randbelow(45) + 1
        weights = [secrets.randbelow(18) + 1 for _ in range(n)]
        values = [secrets.randbelow(80) + 1 for _ in range(n)]
        cases.append((capacity, weights, values))

    for capacity, weights, values in cases:
        n = len(weights)
        w_array = (ctypes.c_int * n)(*weights)
        v_array = (ctypes.c_int * n)(*values)
        actual = fn(capacity, w_array, v_array, n)
        wanted = expected(capacity, weights, values)
        assert actual == wanted, (
            f"calculate_optimal_score({capacity}, {weights}, {values}, {n}) "
            f"returned {actual}, expected {wanted}"
        )


def test_listens_only_on_ipv4_loopback():
    port_hex = format(8080, "04X")
    listeners = []
    for path, ipv6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                local_addr, local_port = fields[1].split(":")
                state = fields[3]
                if local_port.upper() == port_hex and state == "0A":
                    listeners.append((local_addr.upper(), ipv6))
    assert listeners, "No listening socket found on port 8080"
    assert all(not ipv6 and addr == "0100007F" for addr, ipv6 in listeners), (
        f"Port 8080 must be bound exclusively to 127.0.0.1; found {listeners}"
    )


def test_large_request_no_crash():
    payloads = [
        f"GET /{'A' * 2000} HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n",
        f"GET /health HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nX-Large: {'B' * 12000}\r\n\r\n",
        f"GET /{'C' * 64000} HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n",
    ]
    for request in payloads:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect(("127.0.0.1", 8080))
            s.sendall(request.encode("ascii"))
            try:
                s.recv(1024)
            except (socket.timeout, ConnectionResetError):
                pass
            s.close()
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass

        time.sleep(0.2)
        try:
            response = requests.get(f"{BASE_URL}/health", timeout=2)
            assert response.status_code == 200, "Server returned non-200 after large request"
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Server crashed or became unresponsive after receiving a large request: {e}")
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0

# Rebuild the submitted source with sanitizers and exercise the actual server loop.
# This catches request-parser overflows that an ordinary survivability probe can miss.
if [ "$ok" -eq 1 ]; then
    gcc -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
        -o /tmp/dashboard_server_asan /home/user/dashboard/server.c >/tmp/asan_build.log 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
cat << 'ASAN_EOF' > /tmp/test_asan_server.py
import os
import signal
import socket
import subprocess
import time
import requests


def listener_inodes(port):
    answer = set()
    wanted = format(port, "04X")
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(":")[1].upper() == wanted and fields[3] == "0A":
                    answer.add(fields[9])
    return answer


def kill_port_owners(port):
    inodes = listener_inodes(port)
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(entry), signal.SIGTERM)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass


proc = None
failed = None
try:
    kill_port_owners(8080)
    deadline = time.time() + 3
    while listener_inodes(8080) and time.time() < deadline:
        time.sleep(0.05)

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
    log = open("/tmp/dashboard_asan.log", "wb")
    proc = subprocess.Popen(["/tmp/dashboard_server_asan"], stdout=log, stderr=log, env=env)

    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("Sanitized server exited during startup")
        try:
            if requests.get("http://127.0.0.1:8080/health", timeout=0.3).status_code == 200:
                break
        except requests.RequestException:
            time.sleep(0.05)
    else:
        raise AssertionError("Sanitized server did not become ready")

    payloads = [
        b"GET /" + b"A" * 3000 + b" HTTP/1.1\r\nHost: localhost\r\n\r\n",
        b"GET /health HTTP/1.1\r\nHost: localhost\r\nX-Huge: " + b"B" * 30000 + b"\r\n\r\n",
    ]
    for payload in payloads:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=2) as s:
                s.sendall(payload)
                try:
                    s.recv(1024)
                except (socket.timeout, ConnectionResetError):
                    pass
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass
        time.sleep(0.2)
        if proc.poll() is not None:
            raise AssertionError("Sanitized server crashed while parsing a large request")
        response = requests.get("http://127.0.0.1:8080/health", timeout=2)
        assert response.status_code == 200
finally:
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    try:
        log.close()
    except Exception:
        pass
    # Restore the submitted compiled service so the final state remains listening.
    subprocess.Popen(
        ["/home/user/dashboard/server"],
        cwd="/home/user/dashboard",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

with open("/tmp/dashboard_asan.log", "r", errors="replace") as f:
    sanitizer_output = f.read()
assert "ERROR: AddressSanitizer" not in sanitizer_output, sanitizer_output
assert "runtime error:" not in sanitizer_output, sanitizer_output
ASAN_EOF
    python3 /tmp/test_asan_server.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
