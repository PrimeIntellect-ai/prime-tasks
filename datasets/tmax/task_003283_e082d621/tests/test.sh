#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import concurrent.futures
import ctypes
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

EXPECTED_BENCH_LINES = [
    "Avg after 10.0: 10.0",
    "Avg after 20.0: 15.0",
    "Avg after 30.0: 20.0",
    "Avg after 40.0: 30.0",
    "Avg after 50.0: 40.0",
    "Execution completed.",
]
EXPECTED_SYMBOLS = {"init_metrics", "record_and_average"}


def run_checked(command, **kwargs):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True, **kwargs)
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            "Command failed: %r\nstdout:\n%s\nstderr:\n%s"
            % (command, exc.stdout, exc.stderr)
        )


def exported_symbols(path):
    result = run_checked(["nm", "-D", "--defined-only", "--format=posix", path])
    symbols = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields:
            symbols.add(fields[0].split("@", 1)[0])
    return symbols


def load_library(path):
    lib = ctypes.CDLL(path)
    lib.init_metrics.argtypes = [ctypes.c_size_t]
    lib.init_metrics.restype = None
    lib.record_and_average.argtypes = [ctypes.c_double]
    lib.record_and_average.restype = ctypes.c_double
    return lib


def assert_close(actual, expected):
    assert math.isfinite(actual), f"Expected a finite average, got {actual!r}"
    tolerance = 1e-10 * max(1.0, abs(expected))
    assert abs(actual - expected) <= tolerance, f"Expected {expected!r}, got {actual!r}"


@pytest.fixture(scope="session")
def rebuilt_library():
    source = "/home/user/metrics.rs"
    with tempfile.TemporaryDirectory() as tmpdir:
        output = os.path.join(tmpdir, "libmetrics_from_source.so")
        run_checked(["rustc", "--crate-type", "cdylib", "-O", source, "-o", output])
        yield output


def test_libmetrics_so_exists():
    """Ensure the compiled dynamic library exists."""
    path = "/home/user/libmetrics.so"
    assert os.path.isfile(path), "/home/user/libmetrics.so does not exist. Did you compile the Rust code to a dynamic library?"
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "libmetrics.so is not an ELF dynamic library."


def test_metrics_source_exists_and_defines_only_requested_ffi():
    source_path = "/home/user/metrics.rs"
    assert os.path.isfile(source_path), "/home/user/metrics.rs does not exist."
    with open(source_path, "r", encoding="utf-8") as handle:
        source = handle.read()
    assert source.strip(), "/home/user/metrics.rs is empty."

    ffi_pattern = re.compile(
        r'(?:pub(?:\s*\([^)]*\))?\s+)?(?:unsafe\s+)?extern\s*"C"\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)'
    )
    ffi_functions = set(ffi_pattern.findall(source))
    assert ffi_functions == EXPECTED_SYMBOLS, (
        "metrics.rs must define exactly the two requested extern \"C\" functions; "
        f"found {sorted(ffi_functions)}"
    )


def test_exactly_two_symbols_are_exported(rebuilt_library):
    assert exported_symbols("/home/user/libmetrics.so") == EXPECTED_SYMBOLS
    assert exported_symbols(rebuilt_library) == EXPECTED_SYMBOLS


def test_bench_run_exists():
    """Ensure the compiled C executable exists."""
    path = "/home/user/bench_run"
    assert os.path.isfile(path), "/home/user/bench_run does not exist. Did you compile bench.c?"
    assert os.access(path, os.X_OK), "/home/user/bench_run is not executable."
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "/home/user/bench_run is not a compiled ELF executable."
    dynamic = run_checked(["readelf", "-d", path]).stdout
    assert "libmetrics.so" in dynamic, "bench_run is not dynamically linked against libmetrics.so."


def test_bench_output_correct():
    """Ensure the benchmark output matches the expected moving average calculations."""
    output_path = "/home/user/bench_output.txt"
    assert os.path.isfile(output_path), f"{output_path} does not exist. Did you run bench_run and redirect its output?"

    with open(output_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == EXPECTED_BENCH_LINES, f"Output in {output_path} does not match expected moving averages."


def test_bench_executes_now_and_matches_saved_output():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    result = run_checked(["/home/user/bench_run"], env=env)
    actual_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert actual_lines == EXPECTED_BENCH_LINES
    with open("/home/user/bench_output.txt", "r") as handle:
        saved_lines = [line.strip() for line in handle if line.strip()]
    assert actual_lines == saved_lines


def test_ffi_correctness_with_custom_c_program():
    """Compile a new C program against libmetrics.so to verify FFI correctness independently."""
    c_code = """
#include <stdio.h>
#include <stddef.h>

extern void init_metrics(size_t capacity);
extern double record_and_average(double latency);

int main() {
    init_metrics(2);
    printf("%.1f\\n", record_and_average(100.0));
    printf("%.1f\\n", record_and_average(200.0));
    printf("%.1f\\n", record_and_average(300.0));
    return 0;
}
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        c_file = os.path.join(tmpdir, "test_ffi.c")
        exe_file = os.path.join(tmpdir, "test_ffi_run")

        with open(c_file, "w") as f:
            f.write(c_code)

        compile_cmd = [
            "gcc", c_file, "-o", exe_file,
            "-L/home/user", "-lmetrics",
            "-Wl,-rpath=/home/user"
        ]
        run_checked(compile_cmd)

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = "/home/user" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
        result = run_checked([exe_file], env=env)
        output = result.stdout.strip().splitlines()

        assert len(output) == 3, "Expected 3 lines of output from test FFI program."
        assert output[0] == "100.0", f"Expected 100.0, got {output[0]}"
        assert output[1] == "150.0", f"Expected 150.0, got {output[1]}"
        assert output[2] == "250.0", f"Expected 250.0, got {output[2]}"


@pytest.mark.parametrize("library_fixture", ["submitted", "rebuilt"])
def test_randomized_ring_buffer_and_resets(library_fixture, rebuilt_library):
    path = "/home/user/libmetrics.so" if library_fixture == "submitted" else rebuilt_library
    lib = load_library(path)
    rng = random.SystemRandom()

    for _ in range(10):
        capacity = rng.randint(1, 31)
        count = rng.randint(capacity + 2, capacity * 4 + 12)
        values = [rng.randint(-500000, 500000) / 16.0 for _ in range(count)]
        current = collections.deque(maxlen=capacity)
        lib.init_metrics(capacity)

        for value in values:
            current.append(value)
            expected = math.fsum(current) / len(current)
            actual = lib.record_and_average(value)
            assert_close(actual, expected)

    # Explicitly ensure init_metrics resets existing state even when capacity changes.
    reset_capacity = rng.randint(2, 19)
    reset_values = [rng.randint(-100000, 100000) / 8.0 for _ in range(reset_capacity + 5)]
    lib.init_metrics(reset_capacity)
    current = collections.deque(maxlen=reset_capacity)
    for value in reset_values:
        current.append(value)
        assert_close(lib.record_and_average(value), math.fsum(current) / len(current))


@pytest.mark.parametrize("library_fixture", ["submitted", "rebuilt"])
def test_thread_safe_concurrent_recording(library_fixture, rebuilt_library):
    path = "/home/user/libmetrics.so" if library_fixture == "submitted" else rebuilt_library
    lib = load_library(path)
    rng = random.SystemRandom()
    worker_count = 12
    per_worker = 400
    values = [rng.randint(-200000, 200000) / 4.0 for _ in range(worker_count * per_worker)]
    chunks = [values[i::worker_count] for i in range(worker_count)]
    probe = rng.randint(-200000, 200000) / 4.0

    # Capacity exceeds the total number of concurrent writes, so the final mean is
    # independent of thread scheduling and detects lost or corrupted updates.
    lib.init_metrics(len(values) + 1)

    def record_chunk(chunk):
        results = []
        for value in chunk:
            results.append(lib.record_and_average(value))
        return results

    with concurrent.futures.ThreadPoolExecutor(max_workers=worker_count) as executor:
        result_groups = list(executor.map(record_chunk, chunks))

    for result in (item for group in result_groups for item in group):
        assert math.isfinite(result), f"Concurrent call returned non-finite value {result!r}"

    final_average = lib.record_and_average(probe)
    expected = math.fsum(values + [probe]) / (len(values) + 1)
    assert_close(final_average, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
