#!/bin/bash
set -u
mkdir -p /logs/verifier

SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

stop_existing_listener() {
python3 <<'PY'
import glob
import os
import signal
import time

inodes = set()
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(path) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10:
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                        inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for fd in glob.glob("/proc/[0-9]*/fd/*"):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith("socket:[") and target[8:-1] in inodes:
        try:
            pids.add(int(fd.split("/")[2]))
        except (ValueError, IndexError):
            pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass

time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
PY
}

run_verification() {
    rm -rf /tmp/math_server_verifier_build
    cmake -S /workspace/math_server -B /tmp/math_server_verifier_build || return 1
    cmake --build /tmp/math_server_verifier_build -j2 || return 1
    test -x /tmp/math_server_verifier_build/math_server || return 1

    stop_existing_listener || return 1
    /tmp/math_server_verifier_build/math_server >/tmp/math_server_verifier.log 2>&1 &
    SERVER_PID=$!

    local ready=0
    for _ in $(seq 1 30); do
        kill -0 "$SERVER_PID" 2>/dev/null || return 1
        if python3 - <<'PY'
import socket
try:
    with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
        pass
except OSError:
    raise SystemExit(1)
PY
        then
            ready=1
            break
        fi
        sleep 0.1
    done
    [ "$ready" -eq 1 ] || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets
import subprocess

import pytest
import requests


def get_oracle_root(a, b, c, d):
    try:
        result = subprocess.run(
            ["/app/oracle_solver", str(a), str(b), str(c), str(d)],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip()
        words = output.split()
        for word in reversed(words):
            try:
                return float(word)
            except ValueError:
                continue
        return float(output)
    except Exception as e:
        pytest.fail(f"Failed to run oracle solver for {a} {b} {c} {d}: {e}")


test_cases = [
    (1.0, -6.0, 11.0, -6.0),
    (1.0, 0.0, 0.0, -8.0),
    (1.0, 1000.0, 1000.0, 1000.0),
    (2.0, -4.0, -22.0, 24.0),
    (1.0, 0.0, 1.0, 0.0),
    (1.0, 3.0, 3.0, 1.0),
]


@pytest.mark.parametrize("a, b, c, d", test_cases)
def test_solve_endpoint(a, b, c, d):
    expected_root = get_oracle_root(a, b, c, d)

    url = "http://127.0.0.1:8080/solve"
    payload = {"a": a, "b": b, "c": c, "d": d}

    try:
        response = requests.post(url, json=payload, timeout=3.0)
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {url} timed out for inputs {payload}. The infinite loop bug might not be fixed.")
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to {url}. Is the server running on port 8080?")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Failed to parse JSON response: {response.text}")

    assert "root" in data, f"Response JSON missing 'root' key: {data}"

    actual_root = data["root"]
    assert isinstance(actual_root, (int, float)), f"Expected 'root' to be a number, got {type(actual_root)}"

    tolerance = 1e-5
    assert math.isclose(actual_root, expected_root, abs_tol=tolerance), \
        f"For inputs {payload}, expected root ~{expected_root}, but got {actual_root} (diff: {abs(actual_root - expected_root)})"


def make_random_cases():
    rng = secrets.SystemRandom()
    cases = set()

    # Strictly monotone cubics with varied signs and scales.
    while len(cases) < 10:
        a = rng.randint(1, 7)
        b = rng.randint(-12, 12)
        c = b * b + rng.randint(1, 15)
        d = rng.choice([i for i in range(-50, 51) if i != 0])
        sign = rng.choice((-1, 1))
        cases.add((float(sign * a), float(sign * b),
                   float(sign * c), float(sign * d)))

    # Cubics with three distinct real roots, all exactly representable binary
    # fractions. Newton iteration from zero has a stable, nontrivial basin.
    while len(cases) < 20:
        root_nums = rng.sample(range(2, 29), 3)
        root_sign = rng.choice((-1, 1))
        roots = [root_sign * n / 4.0 for n in root_nums]
        a = rng.choice((-1, 1)) * rng.randint(1, 5) / 2.0
        r1, r2, r3 = roots
        b = -a * (r1 + r2 + r3)
        c = a * (r1 * r2 + r1 * r3 + r2 * r3)
        d = -a * r1 * r2 * r3
        cases.add((a, b, c, d))

    return list(cases)


def test_randomized_unseen_coefficients():
    for coefficients in make_random_cases():
        test_solve_endpoint(*coefficients)
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
    kill -0 "$SERVER_PID" 2>/dev/null || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
