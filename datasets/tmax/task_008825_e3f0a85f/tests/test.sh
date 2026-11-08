#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import shutil
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/rust_rate_limiter"
SO_PATH = PROJECT + "/target/release/librust_rate_limiter.so"
BENCHMARK = "/home/user/benchmark.py"
JSON_PATH = "/home/user/benchmark_result.json"


def assert_valid_result():
    assert os.path.isfile(JSON_PATH), f"Expected JSON file not found at {JSON_PATH}."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "success_count" in data, "JSON missing 'success_count' key."
    assert "time_taken_ms" in data, "JSON missing 'time_taken_ms' key."
    assert set(data) == {"success_count", "time_taken_ms"}, "JSON must contain exactly the required keys."
    assert data["success_count"] == 10, f"Expected success_count to be 10, got {data['success_count']}."

    time_taken = data["time_taken_ms"]
    assert isinstance(time_taken, (float, int)) and not isinstance(time_taken, bool), \
        f"Expected time_taken_ms to be a number, got {type(time_taken)}."
    assert time_taken > 0, f"Expected time_taken_ms to be strictly greater than 0, got {time_taken}."


def test_project_builds_and_real_library_behavior():
    result = subprocess.run(
        ["cargo", "build", "--release"], cwd=PROJECT,
        capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, f"cargo build --release failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SO_PATH), f"Compiled shared library not found at {SO_PATH}."

    probe = r'''
import ctypes
lib = ctypes.CDLL("/home/user/rust_rate_limiter/target/release/librust_rate_limiter.so")
fn = lib.check_rate_limit
fn.argtypes = [ctypes.c_int]
fn.restype = ctypes.c_bool
print(sum(bool(fn(42)) for _ in range(1000)))
'''
    result = subprocess.run(["python3", "-c", probe], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Calling the compiled library failed:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.strip() == "10", \
        f"The real library must allow exactly 10 of 1000 calls for user 42; got {result.stdout!r}."


def test_benchmark_result_json():
    assert os.path.isfile(BENCHMARK), f"Expected benchmark script not found at {BENCHMARK}."
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)

    result = subprocess.run(
        ["python3", BENCHMARK], cwd="/home/user",
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"benchmark.py failed:\n{result.stdout}\n{result.stderr}"
    assert_valid_result()


def test_benchmark_makes_exactly_1000_calls_for_user_42():
    # Temporarily substitute an instrumented library at the required path. This
    # observes calls made by benchmark.py without trusting its self-reported JSON.
    spy_source = r'''
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::atomic::{AtomicUsize, Ordering};

static COUNT: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn check_rate_limit(user_id: i32) -> bool {
    if let Ok(path) = std::env::var("RATE_LIMIT_TRACE") {
        let mut f = OpenOptions::new().create(true).append(true).open(path).unwrap();
        writeln!(f, "{}", user_id).unwrap();
    }
    if user_id != 42 {
        return false;
    }
    COUNT.fetch_add(1, Ordering::SeqCst) < 10
}
'''

    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "spy.rs")
        spy_so = os.path.join(td, "librust_rate_limiter.so")
        backup = os.path.join(td, "original.so")
        trace = os.path.join(td, "calls.txt")
        with open(source, "w") as f:
            f.write(spy_source)

        compiled = subprocess.run(
            ["rustc", "--crate-type", "cdylib", "-O", source, "-o", spy_so],
            capture_output=True, text=True, timeout=60
        )
        assert compiled.returncode == 0, f"Could not build verifier instrumentation:\n{compiled.stderr}"

        os.replace(SO_PATH, backup)
        try:
            shutil.copy2(spy_so, SO_PATH)
            if os.path.exists(JSON_PATH):
                os.unlink(JSON_PATH)
            env = os.environ.copy()
            env["RATE_LIMIT_TRACE"] = trace
            result = subprocess.run(
                ["python3", BENCHMARK], cwd="/home/user", env=env,
                capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, f"Instrumented benchmark.py run failed:\n{result.stdout}\n{result.stderr}"
            assert os.path.isfile(trace), "benchmark.py did not call check_rate_limit from the required shared library."
            with open(trace) as f:
                calls = [int(line.strip()) for line in f if line.strip()]
            assert len(calls) == 1000, f"Expected exactly 1000 check_rate_limit calls, got {len(calls)}."
            assert all(user_id == 42 for user_id in calls), "Every check_rate_limit call must use user_id 42."
            assert_valid_result()
        finally:
            if os.path.exists(SO_PATH):
                os.unlink(SO_PATH)
            os.replace(backup, SO_PATH)


def test_shared_library_exists():
    assert os.path.isfile(SO_PATH), f"Compiled shared library not found at {SO_PATH}. Did you compile in release mode?"


def test_symbol_exported():
    assert os.path.isfile(SO_PATH), "Shared library missing, cannot check symbols."

    result = subprocess.run(["nm", "-D", SO_PATH], capture_output=True, text=True)
    if result.returncode != 0:
        result = subprocess.run(["nm", SO_PATH], capture_output=True, text=True)

    output = result.stdout
    found = False
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] == "check_rate_limit":
            found = True
            break
        elif len(parts) >= 2 and parts[1] == "check_rate_limit":
            found = True
            break

    assert found, "Symbol 'check_rate_limit' not found in the shared library. Ensure #[no_mangle] and extern \"C\" are used."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
