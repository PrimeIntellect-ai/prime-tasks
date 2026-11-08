#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import subprocess
import pytest

LIBRARY_PATH = "/app/libfastcrc/libfastcrc.so"
BENCHMARK_PATH = "/app/benchmark.py"

EXPECTED_BENCHMARK = b"""import ctypes
import time
import os
import sys

def py_checksum(data):
    checksum = 0
    for i in range(len(data)):
        for j in range(100):
            checksum ^= (data[i] << (j % 8))
            checksum &= 0xFFFFFFFF
        checksum = (checksum + data[i]) & 0xFFFFFFFF
    return checksum

def main():
    if not os.path.exists('/app/libfastcrc/libfastcrc.so'):
        print("0.0")
        return

    lib = ctypes.CDLL('/app/libfastcrc/libfastcrc.so')
    lib.compute_checksum_and_serialize.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    lib.compute_checksum_and_serialize.restype = ctypes.c_uint32

    data = bytes(os.urandom(10000))
    c_data = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)

    # Warmup
    py_checksum(data[:10])
    lib.compute_checksum_and_serialize(c_data, 10)

    start = time.time()
    for _ in range(10):
        py_checksum(data)
    py_time = time.time() - start

    start = time.time()
    for _ in range(10):
        lib.compute_checksum_and_serialize(c_data, len(data))
    c_time = time.time() - start

    if c_time == 0:
        c_time = 0.000001

    speedup = py_time / c_time
    print(f"Speedup: {speedup:.2f}")

    # Write just the float for the verifier
    with open('/tmp/metric.txt', 'w') as f:
        f.write(str(speedup))

if __name__ == '__main__':
    main()
"""


def py_checksum(data):
    checksum = 0
    for value in data:
        for j in range(100):
            checksum ^= value << (j % 8)
            checksum &= 0xFFFFFFFF
        checksum = (checksum + value) & 0xFFFFFFFF
    return checksum


def load_function():
    lib = ctypes.CDLL(LIBRARY_PATH)
    try:
        function = lib.compute_checksum_and_serialize
    except AttributeError:
        pytest.fail("libfastcrc.so does not export compute_checksum_and_serialize")
    function.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    function.restype = ctypes.c_uint32
    return function


def call_checksum(function, data):
    c_data = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
    return function(c_data, len(data))


def test_libfastcrc_so_exists():
    assert os.path.isfile(LIBRARY_PATH), (
        f"File {LIBRARY_PATH} is missing. "
        "Did you successfully build the library and leave it at the expected path?"
    )


def test_checksum_matches_python_reference():
    function = load_function()
    rng = random.SystemRandom()
    vectors = [
        b"",
        b"\x00",
        b"\xff",
        bytes(range(256)),
        bytes([0, 255, 1, 254]) * 257,
    ]
    vectors.extend(bytes(rng.randrange(256) for _ in range(length))
                   for length in (2, 7, 31, 257, 4096, 10000))

    for data in vectors:
        actual = call_checksum(function, data)
        expected = py_checksum(data)
        assert actual == expected, (
            f"Checksum mismatch for input of length {len(data)}: "
            f"C returned {actual:#010x}, Python returned {expected:#010x}"
        )


def test_benchmark_speedup():
    assert os.path.isfile(BENCHMARK_PATH), f"Benchmark script {BENCHMARK_PATH} is missing."
    with open(BENCHMARK_PATH, "rb") as f:
        actual_benchmark = f.read()
    assert actual_benchmark == EXPECTED_BENCHMARK, (
        "/app/benchmark.py was modified; the instruction requires it to remain unchanged."
    )

    metric_file = "/tmp/metric.txt"
    if os.path.exists(metric_file):
        os.remove(metric_file)

    result = subprocess.run(
        ["python3", BENCHMARK_PATH],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, (
        f"benchmark.py failed to run.\n"
        f"stdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )

    assert os.path.isfile(metric_file), (
        f"Metric file {metric_file} was not created. "
        "The benchmark script might have exited early or failed to load the shared library."
    )

    with open(metric_file, "r") as f:
        content = f.read().strip()

    try:
        speedup = float(content)
    except ValueError:
        pytest.fail(f"Could not parse speedup from {metric_file}. Content: {content}")

    assert speedup >= 15.0, (
        f"Speedup is {speedup:.2f}x, which is less than the required threshold of 15.0x. "
        "Further optimization of the C implementation is required."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
