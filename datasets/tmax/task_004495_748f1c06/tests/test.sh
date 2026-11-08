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
import math
import os
import random
import shutil
import socket
import struct
import subprocess
import time

import pytest
import requests


def test_recovered_csv():
    journal_path = "/app/data/journal.bin"
    recovered_path = "/app/data/recovered.csv"

    assert os.path.exists(journal_path), f"Missing {journal_path}"
    assert os.path.exists(recovered_path), f"Missing {recovered_path}"

    expected_floats = []
    with open(journal_path, "rb") as f:
        while True:
            chunk = f.read(16)
            if len(chunk) < 16:
                break

            magic, = struct.unpack("<I", chunk[0:4])
            if magic != 0xDEADBEEF:
                break

            val_float, = struct.unpack("<d", chunk[4:12])
            half1, half2 = struct.unpack("<II", chunk[4:12])
            expected_checksum = half1 ^ half2
            actual_checksum, = struct.unpack("<I", chunk[12:16])
            if actual_checksum != expected_checksum:
                break

            expected_floats.append(val_float)

    with open(recovered_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_floats), (
        f"Expected {len(expected_floats)} lines in recovered.csv, got {len(lines)}"
    )
    for i, (actual_str, expected_val) in enumerate(zip(lines, expected_floats)):
        expected_str = f"{expected_val:.6f}"
        assert actual_str == expected_str, (
            f"Line {i + 1} mismatch: expected {expected_str}, got {actual_str}"
        )


def post_compute(values, timeout=2.0):
    url = "http://127.0.0.1:8080/compute"
    try:
        response = requests.post(url, json={"data": values}, timeout=timeout)
    except requests.exceptions.Timeout:
        pytest.fail("Request timed out - the backend is likely in an infinite loop.")
    except requests.exceptions.ConnectionError:
        pytest.fail("Connection error - Nginx or backend is not running.")

    assert response.status_code == 200, (
        f"Expected status 200, got {response.status_code}. Body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Invalid JSON response: {response.text}")
    assert "variance" in data, f"Missing 'variance' in response: {data}"
    assert isinstance(data["variance"], (int, float)), f"Non-numeric variance: {data}"
    return float(data["variance"])


def stable_population_variance(values):
    mean = math.fsum(values) / len(values)
    return math.fsum((x - mean) * (x - mean) for x in values) / len(values)


def test_compute_endpoint_numerical_stability():
    payload = [10000000000000000.0, 10000000000000001.0, 10000000000000002.0]
    variance = post_compute(payload)
    assert math.isclose(variance, 1.0, rel_tol=1e-5), (
        f"Expected variance ~1.0, got {variance}"
    )


def test_compute_endpoint_parses_and_computes_multiple_payloads():
    rng = random.SystemRandom()
    cases = [
        [1.0, 2.0, 3.0, 4.0],
        [-4.0, -1.0, 2.0, 8.0],
        [1.0e12, 1.0e12 + 2.0, 1.0e12 + 5.0, 1.0e12 + 9.0],
    ]
    for _ in range(5):
        n = rng.randrange(3, 9)
        cases.append([float(rng.randrange(-10000, 10001)) / 8.0 for _ in range(n)])

    for values in cases:
        expected = stable_population_variance(values)
        actual = post_compute(values)
        assert math.isfinite(actual), f"Non-finite variance for {values}: {actual}"
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), (
            f"Wrong variance for {values}: expected {expected}, got {actual}"
        )


def get_backend_pid():
    result = subprocess.run(["pgrep", "-x", "backend"], capture_output=True, text=True)
    for item in result.stdout.split():
        pid = int(item)
        if os.path.exists(f"/proc/{pid}/status"):
            return pid
    return None


def get_thread_count(pid):
    status_file = f"/proc/{pid}/status"
    if not os.path.exists(status_file):
        return None
    with open(status_file, "r") as f:
        for line in f:
            if line.startswith("Threads:"):
                return int(line.split()[1])
    return None


def test_running_backend_is_current_binary():
    pid = get_backend_pid()
    assert pid is not None, "Could not find backend process running on port 8081"
    assert os.path.exists("/app/src/backend"), "Compiled backend is missing"
    try:
        assert os.path.samefile(f"/proc/{pid}/exe", "/app/src/backend"), (
            "Running backend is not the compiled /app/src/backend artifact"
        )
    except FileNotFoundError:
        pytest.fail("Running backend executable is stale or deleted")


def test_thread_leak_on_chunked_disconnect():
    pid = get_backend_pid()
    assert pid is not None, "Could not find backend process running on port 8081"

    initial_threads = get_thread_count(pid)
    assert initial_threads is not None, "Could not read thread count"

    # Exercise the backend's chunked request path directly. Each client advertises
    # a large chunk, sends only part of it, and disconnects before its terminating
    # CRLF and zero-sized chunk.
    for _ in range(80):
        try:
            with socket.create_connection(("127.0.0.1", 8081), timeout=1.0) as s:
                s.sendall(
                    b"POST /compute HTTP/1.1\r\n"
                    b"Host: 127.0.0.1:8081\r\n"
                    b"Transfer-Encoding: chunked\r\n"
                    b"Content-Type: application/json\r\n"
                    b"Connection: close\r\n\r\n"
                    b"1000\r\n{\"data\": [1.0, 2.0,"
                )
        except OSError:
            pass

    time.sleep(2.0)
    final_threads = get_thread_count(pid)
    assert final_threads is not None, "Could not read thread count after test"
    assert final_threads < 20, (
        f"Thread leak detected! Thread count is {final_threads} (initial was {initial_threads})"
    )
    assert final_threads <= initial_threads + 2, (
        f"Chunked disconnects leaked threads: {initial_threads} -> {final_threads}"
    )

    # The server must remain responsive after all disconnects.
    assert math.isclose(post_compute([1.0, 2.0, 3.0]), 2.0 / 3.0,
                        rel_tol=1e-5, abs_tol=1e-5)


def test_makefile_builds_backend_and_fuzzer():
    build_dir = "/tmp/src_build_check"
    shutil.rmtree(build_dir, ignore_errors=True)
    shutil.copytree("/app/src", build_dir)

    clean = subprocess.run(["make", "-C", build_dir, "clean"],
                           capture_output=True, text=True)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"

    # Remove copied ELF artifacts even if the submitted clean rule forgot them.
    for name in os.listdir(build_dir):
        path = os.path.join(build_dir, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    os.unlink(path)

    built = subprocess.run(["make", "-C", build_dir, "all"],
                           capture_output=True, text=True, timeout=60)
    assert built.returncode == 0, f"make all failed:\n{built.stdout}\n{built.stderr}"

    elf_executables = []
    for name in os.listdir(build_dir):
        path = os.path.join(build_dir, name)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    elf_executables.append(name)
    assert len(elf_executables) >= 2, (
        f"Makefile all target did not build both backend and fuzzer: {elf_executables}"
    )


def test_fuzz_test_exists_compiles_links_calls_and_runs():
    fuzz_src = "/app/src/fuzz_test.cpp"
    backend_src = "/app/src/backend.cpp"
    assert os.path.exists(fuzz_src), f"Missing fuzz test source: {fuzz_src}"

    with open(fuzz_src, "r") as f:
        content = f.read()
    assert "LLVMFuzzerTestOneInput" in content, (
        f"Function LLVMFuzzerTestOneInput not found in {fuzz_src}"
    )

    fuzz_obj = "/tmp/fuzz_verify.o"
    backend_obj = "/tmp/backend_verify.o"
    fuzz_bin = "/tmp/fuzz_verify"

    cmd = ["clang++", "-std=c++11", "-O0", "-pthread", "-fsanitize=fuzzer-no-link",
           "-I/app/src", "-c", fuzz_src, "-o", fuzz_obj]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"fuzz_test.cpp does not compile:\n{result.stderr}"

    symbols = subprocess.run(["nm", "-C", fuzz_obj], capture_output=True,
                             text=True, timeout=10)
    assert symbols.returncode == 0, f"Could not inspect fuzz object: {symbols.stderr}"
    assert "U compute_variance(" in symbols.stdout, (
        "LLVMFuzzerTestOneInput must call the external compute_variance function"
    )

    cmd = ["clang++", "-std=c++11", "-O0", "-pthread", "-I/app/src",
           "-Dmain=backend_server_main", "-c", backend_src, "-o", backend_obj]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"backend.cpp does not compile for linking:\n{result.stderr}"

    cmd = ["clang++", "-pthread", "-fsanitize=fuzzer", fuzz_obj, backend_obj,
           "-o", fuzz_bin]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f"Fuzzer does not link against backend.cpp compute_variance:\n{result.stderr}"
    )

    corpus = "/tmp/fuzz_corpus"
    shutil.rmtree(corpus, ignore_errors=True)
    os.mkdir(corpus)
    with open(os.path.join(corpus, "short"), "wb") as f:
        f.write(b"x")
    with open(os.path.join(corpus, "finite"), "wb") as f:
        f.write(struct.pack("<ddd", 1.0, 2.0, 3.0))
    with open(os.path.join(corpus, "nan"), "wb") as f:
        f.write(struct.pack("<ddd", float("nan"), 1.0e200, -1.0e200))

    try:
        run = subprocess.run([fuzz_bin, "-runs=500", "-max_len=256", corpus],
                             capture_output=True, text=True, timeout=12)
    except subprocess.TimeoutExpired:
        pytest.fail("Fuzzer hung while exercising compute_variance")
    assert run.returncode == 0, f"Fuzzer failed:\n{run.stdout}\n{run.stderr}"


def test_compute_variance_function_directly():
    harness = "/tmp/variance_harness.cpp"
    binary = "/tmp/variance_harness"
    backend_obj = "/tmp/backend_direct.o"
    with open(harness, "w") as f:
        f.write(r'''
#include <cmath>
#include <iostream>
#include <vector>
double compute_variance(const std::vector<double>&);
int main() {
    struct Case { std::vector<double> values; double expected; };
    std::vector<Case> cases = {
        {{1.0, 2.0, 3.0}, 2.0 / 3.0},
        {{-4.0, -1.0, 2.0, 8.0}, 19.6875},
        {{1.0e12, 1.0e12 + 1.0, 1.0e12 + 2.0, 1.0e12 + 3.0}, 1.25},
        {{1.0e200, 1.0e200, 1.0e200}, 0.0}
    };
    for (const auto& c : cases) {
        double got = compute_variance(c.values);
        double tolerance = 1e-10 * std::max(1.0, std::fabs(c.expected));
        if (!std::isfinite(got) || std::fabs(got - c.expected) > tolerance) {
            std::cerr << "expected " << c.expected << ", got " << got << "\n";
            return 1;
        }
    }
    return 0;
}
''')

    compile_backend = subprocess.run(
        ["clang++", "-std=c++11", "-O2", "-pthread", "-I/app/src",
         "-Dmain=backend_server_main", "-c", "/app/src/backend.cpp", "-o", backend_obj],
        capture_output=True, text=True, timeout=60)
    assert compile_backend.returncode == 0, compile_backend.stderr

    link = subprocess.run(
        ["clang++", "-std=c++11", "-O2", "-pthread", harness, backend_obj, "-o", binary],
        capture_output=True, text=True, timeout=60)
    assert link.returncode == 0, f"Could not link compute_variance harness:\n{link.stderr}"

    try:
        run = subprocess.run([binary], capture_output=True, text=True, timeout=4)
    except subprocess.TimeoutExpired:
        pytest.fail("compute_variance hung on a numerical-stability regression case")
    assert run.returncode == 0, f"compute_variance regression failure: {run.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
