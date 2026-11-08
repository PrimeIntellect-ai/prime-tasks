#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import math
import os
import random
import re
import signal
import subprocess
import time
import urllib.request

import pytest

URL = "http://127.0.0.1:8080/api/v1/compute"
CPP_DIR = "/home/user/src/cpp"
GO_DIR = "/home/user/src/go"
SERVER_BIN = "/tmp/submission_server"
normal_proc = None


def post_values(values, timeout=5):
    payload = json.dumps({"values": values}).encode("utf-8")
    req = urllib.request.Request(
        URL, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        data = json.loads(response.read().decode("utf-8"))
        assert "result" in data, "Response JSON missing 'result' key."
        assert isinstance(data["result"], (int, float)), "Result must be numeric."
        return float(data["result"])


def listener_pids(port=8080):
    wanted = f":{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].upper().endswith(wanted) and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def kill_listeners():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def start_server(extra_library_path=CPP_DIR):
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = extra_library_path + ((":" + old) if old else "")
    proc = subprocess.Popen(
        [SERVER_BIN], cwd=GO_DIR, env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Rebuilt Go server exited early with status {proc.returncode}")
        try:
            post_values([0.25, -0.25])
            return proc
        except Exception as exc:
            last_error = exc
            time.sleep(0.05)
    proc.terminate()
    pytest.fail(f"Rebuilt Go server did not become ready: {last_error}")


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    kill_listeners()


def test_status_file():
    status_file = "/home/user/status.txt"
    assert os.path.isfile(status_file), f"Status file {status_file} not found. Did you create it?"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert "READY" in content, f"Expected 'READY' in {status_file}, found '{content}'."


def test_build_artifacts_and_start_rebuilt_service():
    global normal_proc
    make = subprocess.run(
        ["make", "-B"], cwd=CPP_DIR, capture_output=True, text=True, timeout=30
    )
    assert make.returncode == 0, f"C++ Makefile build failed:\n{make.stdout}\n{make.stderr}"

    library = os.path.join(CPP_DIR, "libcompute.so")
    assert os.path.isfile(library), "Makefile did not produce libcompute.so"
    elf = subprocess.run(["readelf", "-h", library], capture_output=True, text=True)
    assert elf.returncode == 0 and re.search(r"Type:\s+DYN", elf.stdout), \
        "libcompute.so is not an ELF shared object"
    symbols = subprocess.run(["nm", "-D", library], capture_output=True, text=True)
    assert symbols.returncode == 0 and re.search(r"\bprocess_array$", symbols.stdout, re.M), \
        "libcompute.so does not export process_array with the required C ABI"

    main_path = os.path.join(GO_DIR, "main.go")
    assert os.path.isfile(main_path), "Go API implementation main.go is missing"
    source = open(main_path, encoding="utf-8").read()
    assert re.search(r'import\s+"C"|import\s*\([^)]*"C"', source, re.S), \
        "main.go does not use cgo"
    assert re.search(r"C\s*\.\s*process_array", source), \
        "main.go does not call the C process_array function"

    build = subprocess.run(
        ["go", "build", "-o", SERVER_BIN, "main.go"], cwd=GO_DIR,
        env={**os.environ, "CGO_ENABLED": "1"}, capture_output=True, text=True, timeout=60
    )
    assert build.returncode == 0, f"Go server failed to build:\n{build.stdout}\n{build.stderr}"
    dynamic = subprocess.run(["readelf", "-d", SERVER_BIN], capture_output=True, text=True)
    assert dynamic.returncode == 0 and "libcompute.so" in dynamic.stdout, \
        "Rebuilt Go server is not dynamically linked to libcompute.so"

    kill_listeners()
    normal_proc = start_server()


def test_api_correctness():
    values = [1.5, 2.5, 3.5, 4.5, 5.5]
    try:
        result = post_values(values)
        assert abs(result - 17.5) < 1e-6, f"Expected result 17.5, got {result}"
    except Exception as e:
        pytest.fail(f"Failed to communicate with API at {URL}: {e}")


def test_api_general_inputs_and_concurrency():
    rng = random.Random(731942)
    cases = [
        [0.0],
        [-3.25, 8.5, -1.125, 0.375],
        [10.0, -10.0, 0.125, 2.75, -0.5, 4.0],
    ]
    for _ in range(45):
        cases.append([rng.uniform(-20.0, 20.0) for _ in range(rng.randint(1, 24))])

    def check(values):
        actual = post_values(values, timeout=8)
        expected = sum(values)
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-6), \
            f"For {values!r}, expected {expected}, got {actual}"

    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as pool:
        futures = [pool.submit(check, values) for values in cases]
        for future in futures:
            future.result()


def test_performance_metric():
    go_code = """package main
import (
    "bytes"
    "fmt"
    "net/http"
    "sync"
    "time"
)
func main() {
    start := time.Now()
    var wg sync.WaitGroup
    payload := []byte(`{"values": [1.5, 2.5, 3.5, 4.5, 5.5]}`)
    for i := 0; i < 1000; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            http.Post("http://127.0.0.1:8080/api/v1/compute", "application/json", bytes.NewBuffer(payload))
        }()
    }
    wg.Wait()
    elapsed := time.Since(start).Milliseconds()
    fmt.Println(elapsed)
}
"""
    script_path = "/tmp/eval_perf.go"
    with open(script_path, "w") as f:
        f.write(go_code)

    try:
        result = subprocess.run(["go", "run", script_path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Go load test failed to run: {result.stderr}"
        latency_ms = int(result.stdout.strip())
        assert latency_ms <= 500, f"Metric threshold failed: latency_ms={latency_ms} > 500"
    except subprocess.TimeoutExpired:
        pytest.fail("Performance test timed out (took longer than 30s). The API is likely too slow or deadlocking.")
    except ValueError:
        pytest.fail(f"Failed to parse performance test output: {result.stdout}")
    except Exception as e:
        pytest.fail(f"Performance test execution failed: {e}")


def test_runtime_really_calls_shared_library():
    global normal_proc
    stop_server(normal_proc)
    normal_proc = None

    shim_dir = "/tmp/verifier_shim"
    os.makedirs(shim_dir, exist_ok=True)
    shim_src = os.path.join(shim_dir, "shim.cpp")
    with open(shim_src, "w") as f:
        f.write(r'''
extern "C" double process_array(const double* arr, int size) {
    double result = 1000003.0 + 17.0 * size;
    for (int i = 0; i < size; ++i) {
        result += arr[i] * (double)(i + 1);
    }
    return result;
}
''')
    shim_lib = os.path.join(shim_dir, "libcompute.so")
    compile_shim = subprocess.run(
        ["g++", "-shared", "-fPIC", "-Wl,-soname,libcompute.so", "-o", shim_lib, shim_src],
        capture_output=True, text=True, timeout=30
    )
    assert compile_shim.returncode == 0, f"Failed to build verifier shim: {compile_shim.stderr}"

    shim_proc = start_server(shim_dir)
    try:
        rng = random.Random(994103)
        for _ in range(12):
            values = [rng.uniform(-7, 7) for _ in range(rng.randint(2, 13))]
            expected = 1000003.0 + 17.0 * len(values)
            for i, value in enumerate(values):
                expected += value * (i + 1)
            actual = post_values(values)
            assert math.isclose(actual, expected, rel_tol=1e-11, abs_tol=1e-6), \
                "API output did not follow the loaded process_array implementation; cgo library call is not in the request path"
    finally:
        stop_server(shim_proc)


def teardown_module(module):
    stop_server(normal_proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
