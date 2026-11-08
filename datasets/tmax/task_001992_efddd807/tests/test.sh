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
import concurrent.futures
import os
import random
import re
import signal
import socket
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

SERVICE_URL = "http://127.0.0.1:8080/api/v1/process"
AUTH = {"Authorization": "Bearer dev_token_99z"}
SERVICE_STATE = {"proc": None}


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and local.rsplit(":", 1)[-1].upper() == wanted:
                        inodes.add(fields[9])
        except OSError:
            pass

    result = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(pid))
                    break
        except OSError:
            pass
    return result


def clear_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def stop_service():
    proc = SERVICE_STATE.get("proc")
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)
    SERVICE_STATE["proc"] = None
    clear_port(8080)


def launch_service():
    proc = subprocess.Popen(
        ["bash", "/app/start.sh"],
        cwd="/app",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    SERVICE_STATE["proc"] = proc
    deadline = time.time() + 30
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"/app/start.sh exited before the service became available (status {proc.returncode})")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.5):
                return
        except OSError:
            time.sleep(0.25)
    pytest.fail("Service did not start on port 8080 within 30 seconds")


@pytest.fixture(scope="session", autouse=True)
def start_services():
    clear_port(8080)
    clear_port(6379)
    launch_service()
    yield
    stop_service()


def test_c_code_fixed():
    path = "/app/legacy/telemetry.c"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "i <= len" not in content, "The bug (i <= len) should be fixed in telemetry.c"


def test_c_implementation_is_memory_safe_and_correct():
    harness = r'''
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include "telemetry.h"

int main(void) {
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0) return 90;
    size_t lengths[] = {0, 1, 2, 17, 257, 1000};
    for (size_t t = 0; t < sizeof(lengths) / sizeof(lengths[0]); ++t) {
        size_t len = lengths[t];
        unsigned char *mem = mmap(NULL, (size_t)page * 2, PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (mem == MAP_FAILED) return 91;
        if (mprotect(mem + page, (size_t)page, PROT_NONE) != 0) return 92;
        int *data = (int *)(mem + page - len * sizeof(int));
        long long expected = 0;
        for (size_t i = 0; i < len; ++i) {
            data[i] = (int)((i * 7919U + t * 101U) % 200001U) - 100000;
            expected += data[i];
        }
        long long actual = process_telemetry(data, len);
        if (actual != expected) {
            fprintf(stderr, "len=%zu expected=%lld actual=%lld\n", len, expected, actual);
            return 10;
        }
        munmap(mem, (size_t)page * 2);
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.c")
        binary_path = os.path.join(td, "harness")
        with open(harness_path, "w") as f:
            f.write(harness)
        built = subprocess.run(
            ["gcc", "-std=c11", "-O0", "-Wall", "-Wextra", "-I/app/legacy",
             harness_path, "/app/legacy/telemetry.c", "-o", binary_path],
            text=True, capture_output=True,
        )
        assert built.returncode == 0, f"Could not compile repaired C library:\n{built.stdout}\n{built.stderr}"
        run = subprocess.run([binary_path], text=True, capture_output=True, timeout=5)
        assert run.returncode == 0, (
            "The repaired C function is incorrect or accessed outside the input array: "
            f"status={run.returncode}\n{run.stdout}\n{run.stderr}"
        )


def test_go_source_declares_cgo_call():
    path = "/app/service/main.go"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path) as f:
        source = f.read()
    assert re.search(r'\bimport\s*(?:\([^)]*)?\s*"C"', source, re.S), "main.go must import C through cgo"
    assert re.search(r'\bC\s*\.\s*process_telemetry\s*\(', source), "main.go must call C.process_telemetry"


def test_auth_missing():
    response = requests.post(
        SERVICE_URL,
        json={"batch_id": "test_auth", "readings": [1, 2, 3]},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized without auth header, got {response.status_code}"


def test_auth_invalid():
    response = requests.post(
        SERVICE_URL,
        headers={"Authorization": "Bearer invalid_token"},
        json={"batch_id": "test_auth_invalid", "readings": [1, 2, 3]},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized with bad token, got {response.status_code}"


def get_redis_key(key: str):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect(("127.0.0.1", 6379))
    encoded = key.encode("utf-8")
    cmd = b"*2\r\n$3\r\nGET\r\n$" + str(len(encoded)).encode() + b"\r\n" + encoded + b"\r\n"
    s.sendall(cmd)
    chunks = []
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        chunks.append(chunk)
        if b"\r\n" in b"".join(chunks)[1:]:
            break
    s.close()
    resp = b"".join(chunks).decode("utf-8")
    if resp.startswith("$-1"):
        return None
    parts = resp.split("\r\n")
    return parts[1] if len(parts) >= 2 else resp


def assert_processed(batch_id, readings, timeout=5):
    expected_sum = sum(readings)
    response = requests.post(
        SERVICE_URL,
        headers=AUTH,
        json={"batch_id": batch_id, "readings": readings},
        timeout=timeout,
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code} with body {response.text}"
    data = response.json()
    assert "result" in data, f"Response JSON missing 'result' key: {data}"
    assert data["result"] == expected_sum, f"Expected result {expected_sum}, got {data['result']}"
    redis_val = get_redis_key(f"batch:{batch_id}")
    assert redis_val == str(expected_sum), f"Expected Redis value {expected_sum}, got {redis_val}"


def test_process_endpoint_small_payload():
    assert_processed("test_small", [10, 20, 30, 40])


def test_process_endpoint_large_payload():
    try:
        assert_processed("test_large", [1] * 5000, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Request failed, possibly due to a crash (OOB read): {e}")


def test_concurrent_random_payloads():
    rng = random.SystemRandom()
    nonce = uuid.uuid4().hex
    jobs = []
    for i in range(28):
        length = 5000 if i in (0, 1) else rng.randint(1, 450)
        readings = [rng.randint(-1000000, 1000000) for _ in range(length)]
        jobs.append((f"concurrent_{nonce}_{i}", readings))

    def send(job):
        batch_id, readings = job
        expected = sum(readings)
        response = requests.post(
            SERVICE_URL,
            headers=AUTH,
            json={"batch_id": batch_id, "readings": readings},
            timeout=15,
        )
        return batch_id, expected, response.status_code, response.text, response.json() if response.status_code == 200 else None

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        results = list(pool.map(send, jobs))

    for batch_id, expected, status, body, data in results:
        assert status == 200, f"Concurrent request failed with {status}: {body}"
        assert data == {"result": expected}, f"Wrong concurrent response for {batch_id}: {data}"
        assert get_redis_key(f"batch:{batch_id}") == str(expected), f"Wrong Redis value for {batch_id}"


def test_running_service_really_calls_rebuilt_c_library():
    path = "/app/legacy/telemetry.c"
    with open(path) as f:
        original = f.read()

    signature = re.compile(
        r'(long\s+long\s+process_telemetry\s*\(\s*int\s*\*\s*([A-Za-z_]\w*)\s*,\s*size_t\s+([A-Za-z_]\w*)\s*\)\s*\{)'
    )
    match = signature.search(original)
    assert match, "Could not find the required process_telemetry function definition"
    data_name, len_name = match.group(2), match.group(3)
    sentinel = 9876543210123
    probe = [314159, -271828, 161803]
    injection = (
        match.group(1)
        + f"\n    if ({len_name} == 3 && {data_name}[0] == 314159 && "
          f"{data_name}[1] == -271828 && {data_name}[2] == 161803) "
          f"return {sentinel}LL;\n"
    )
    mutated = original[:match.start()] + injection + original[match.end():]

    stop_service()
    clear_port(6379)
    try:
        with open(path, "w") as f:
            f.write(mutated)
        launch_service()
        batch_id = "cgo_probe_" + uuid.uuid4().hex
        response = requests.post(
            SERVICE_URL,
            headers=AUTH,
            json={"batch_id": batch_id, "readings": probe},
            timeout=10,
        )
        assert response.status_code == 200, f"Rebuilt service rejected C-call probe: {response.status_code} {response.text}"
        data = response.json()
        assert data.get("result") == sentinel, (
            "The running Go service did not use the rebuilt process_telemetry C function; "
            f"got {data}"
        )
        assert get_redis_key(f"batch:{batch_id}") == str(sentinel), "C result was not cached in Redis"
    finally:
        with open(path, "w") as f:
            f.write(original)
        stop_service()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
