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
import glob
import math
import os
import secrets
import signal
import socket
import subprocess
import time
import uuid

import pytest
import requests

SERVICE_PROCESS = None


def listener_pids(port):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if local.rsplit(":", 1)[-1].upper() == wanted_port and state == "0A":
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[-1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def stop_existing_service():
    pids = listener_pids(8080)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if SERVICE_PROCESS.poll() is not None:
            pytest.fail("The compiled Go service exited before listening on port 8080")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("The compiled Go service did not listen on port 8080")


@pytest.fixture(scope="session", autouse=True)
def run_submitted_go_service():
    global SERVICE_PROCESS
    generator_dir = "/app/generator"
    go_files = sorted(
        p for p in glob.glob(os.path.join(generator_dir, "*.go"))
        if not p.endswith("_test.go")
    )
    assert go_files, "No Go source files were found in /app/generator"

    binary = "/tmp/verifier-generator"
    if os.path.exists(os.path.join(generator_dir, "go.mod")):
        command = ["go", "build", "-o", binary, "."]
    else:
        command = ["go", "build", "-o", binary] + go_files
    result = subprocess.run(
        command, cwd=generator_dir, capture_output=True, text=True, timeout=90
    )
    assert result.returncode == 0, f"Go service failed to build:\n{result.stdout}\n{result.stderr}"

    stop_existing_service()
    log = open("/tmp/verifier-generator.log", "w")
    SERVICE_PROCESS = subprocess.Popen(
        [binary], cwd=generator_dir, stdout=log, stderr=subprocess.STDOUT
    )
    try:
        wait_for_port(8080)
        yield
    finally:
        if SERVICE_PROCESS.poll() is None:
            SERVICE_PROCESS.terminate()
            try:
                SERVICE_PROCESS.wait(timeout=3)
            except subprocess.TimeoutExpired:
                SERVICE_PROCESS.kill()
        log.close()


def redis_delete(key):
    subprocess.run(["redis-cli", "DEL", key], capture_output=True, text=True, check=True)


def redis_values(key):
    try:
        result = subprocess.run(
            ["redis-cli", "LRANGE", key, "0", "-1"],
            capture_output=True, text=True, check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query Redis: {e.stderr}")
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    try:
        values = [float(x) for x in lines]
    except ValueError as e:
        pytest.fail(f"Failed to parse Redis list values as floats: {e}")
    assert all(math.isfinite(x) for x in values), f"Redis contained non-finite values: {values}"
    return lines, values


def forward_euler(alpha, t_end, dt):
    dx = 0.1
    u = [4.0 * (i * dx) * (1.0 - i * dx) for i in range(11)]
    u[0] = 0.0
    u[-1] = 0.0
    steps = int(round(t_end / dt))
    assert abs(steps * dt - t_end) < 1e-12
    coefficient = alpha * dt / (dx * dx)
    for _ in range(steps):
        old = u
        u = [0.0] * 11
        for i in range(1, 10):
            u[i] = old[i] + coefficient * (old[i + 1] - 2.0 * old[i] + old[i - 1])
    return u


def converged_solution(alpha, t_end):
    dt = 0.05
    coarse = forward_euler(alpha, t_end, dt)
    for _ in range(40):
        dt /= 2.0
        fine = forward_euler(alpha, t_end, dt)
        if max(abs(a - b) for a, b in zip(fine, coarse)) <= 1e-4:
            return fine
        coarse = fine
    raise AssertionError("Reference convergence loop did not converge")


def assert_vector_close(actual, expected):
    assert len(actual) == 11, f"Expected 11 values, got {len(actual)}: {actual}"
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert abs(got - want) <= 3e-6, (
            f"Incorrect solution at spatial index {i}: got {got}, expected {want}"
        )


def post_solution(sim_id, alpha, t_end):
    response = requests.post(
        "http://127.0.0.1:8080/solve",
        json={"id": sim_id, "alpha": alpha, "t_end": t_end},
        timeout=15,
    )
    assert response.status_code == 200, (
        f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"
    )


def test_pde_solver():
    url = "http://127.0.0.1:8080/solve"
    payload = {"id": "test_verification", "alpha": 0.1, "t_end": 0.1}
    redis_delete("solution:test_verification")

    try:
        response = requests.post(url, json=payload, timeout=15)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service on port 8080 or request failed: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"

    lines, values = redis_values("solution:test_verification")

    assert len(lines) == 11, f"Expected 11 elements in Redis list 'solution:test_verification', got {len(lines)}: {lines}"
    assert abs(values[0]) < 1e-6, f"Expected first element to be 0.0, got {values[0]}"
    assert abs(values[-1]) < 1e-6, f"Expected last element to be 0.0, got {values[-1]}"

    midpoint = values[5]
    assert 0.720 <= midpoint <= 0.730, f"Expected midpoint (index 5) to be between 0.720 and 0.730, got {midpoint}"
    assert_vector_close(values, converged_solution(0.1, 0.1))


def test_varying_parameters_and_rpush_append():
    rng = secrets.SystemRandom()
    sim_id = "dynamic_" + uuid.uuid4().hex
    key = "solution:" + sim_id
    redis_delete(key)

    alpha1 = round(rng.uniform(0.025, 0.085), 6)
    alpha2 = round(rng.uniform(0.115, 0.19), 6)
    t1, t2 = rng.sample([0.05, 0.10, 0.15, 0.20], 2)

    post_solution(sim_id, alpha1, t1)
    _, first = redis_values(key)
    assert_vector_close(first, converged_solution(alpha1, t1))

    post_solution(sim_id, alpha2, t2)
    _, appended = redis_values(key)
    assert len(appended) == 22, f"RPUSH should append 11 values per request; got {len(appended)}"
    assert_vector_close(appended[:11], converged_solution(alpha1, t1))
    assert_vector_close(appended[11:], converged_solution(alpha2, t2))


def test_additional_random_solution():
    rng = secrets.SystemRandom()
    sim_id = "random_" + uuid.uuid4().hex
    key = "solution:" + sim_id
    redis_delete(key)
    alpha = round(rng.uniform(0.03, 0.18), 6)
    t_end = rng.choice([0.05, 0.10, 0.15, 0.20])
    post_solution(sim_id, alpha, t_end)
    _, values = redis_values(key)
    assert_vector_close(values, converged_solution(alpha, t_end))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
