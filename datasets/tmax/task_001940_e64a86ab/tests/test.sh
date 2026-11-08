#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import random
import secrets
import time
import urllib.parse
import urllib.request

import pytest

LIB_PATH = "/app/libevaluator.so"

lib = ctypes.CDLL(LIB_PATH)
evaluate = lib.evaluate_expr_v2
evaluate.argtypes = [ctypes.c_char_p]
evaluate.restype = ctypes.c_double


def reference(expr):
    return float(evaluate(expr.encode("utf-8")))


def api_calculate(expr):
    query = urllib.parse.urlencode({"expr": expr})
    url = "http://127.0.0.1:9090/calculate?" + query
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            status = response.status
            body = response.read().decode("utf-8").strip()
    except Exception as exc:
        pytest.fail(f"Failed to call the API on 127.0.0.1:9090: {exc}")

    assert status == 200, f"Expected HTTP 200, got {status}"
    try:
        return float(body)
    except ValueError:
        pytest.fail(f"API response body could not be parsed as a float: {body!r}")


def listener_pids():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            host_hex, port_hex = fields[1].split(":")
            if int(port_hex, 16) != 9090:
                continue
            if table.endswith("tcp") and host_hex != "0100007F":
                continue
            if table.endswith("tcp6") and host_hex.upper() not in {
                "0000000000000000FFFF00000100007F",
                "00000000000000000000000001000000",
            }:
                continue
            socket_inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                pids.add(int(entry))
                break
    return pids


def test_api_running_and_correct():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    expressions = [
        "10+20*3",
        "100 * 50 + 20",
        str(rng.randint(-1000000, 1000000)),
        f"{rng.uniform(-10000, 10000):.12f}",
        f"prefix-{secrets.token_hex(8)}-10+20*3-suffix-{secrets.token_hex(8)}",
        f"100 * 50 + 20 #{secrets.token_hex(12)}",
    ]

    for expr in expressions:
        expected = reference(expr)
        actual = api_calculate(expr)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"Expected {expected!r} for {expr!r}, got {actual!r}"
        )

    pids = listener_pids()
    assert pids, "No process is listening specifically on 127.0.0.1:9090"
    loaded_by_listener = False
    for pid in pids:
        try:
            with open(f"/proc/{pid}/maps") as handle:
                maps = handle.read()
        except OSError:
            continue
        if LIB_PATH in maps:
            loaded_by_listener = True
            break
    assert loaded_by_listener, (
        "The process serving 127.0.0.1:9090 has not loaded /app/libevaluator.so"
    )


def test_file_organization():
    source_dir = "/home/user/configs"
    high_dir = "/home/user/configs_high"
    low_dir = "/home/user/configs_low"
    original_contents = {
        "file1.txt": "50 * 3",
        "file2.txt": "10 + 20",
    }

    assert os.path.isdir(high_dir), f"Expected directory {high_dir} to exist"
    assert os.path.isdir(low_dir), f"Expected directory {low_dir} to exist"

    for name, expression in original_contents.items():
        result = reference(expression)
        expected_dir = high_dir if math.isfinite(result) and result > 100.0 else low_dir
        wrong_dir = low_dir if expected_dir == high_dir else high_dir
        expected_path = os.path.join(expected_dir, name)

        assert os.path.isfile(expected_path), (
            f"Expected {name} in {expected_dir}; the library evaluates "
            f"{expression!r} as {result!r}"
        )
        with open(expected_path) as handle:
            assert handle.read().splitlines()[0] == expression
        assert not os.path.exists(os.path.join(wrong_dir, name)), (
            f"{name} was also placed in the wrong output directory"
        )
        assert not os.path.exists(os.path.join(source_dir, name)), (
            f"{name} should have been moved, but still exists in {source_dir}"
        )


def test_benchmark_file():
    benchmark_file = "/home/user/benchmark.txt"
    assert os.path.isfile(benchmark_file), (
        f"Expected benchmark file {benchmark_file} does not exist"
    )

    with open(benchmark_file) as handle:
        content = handle.read().strip()
    try:
        time_val = float(content)
    except ValueError:
        pytest.fail(f"Benchmark file does not contain a valid float: {content!r}")

    assert time_val >= 0.0, f"Benchmark time should be nonnegative, got {time_val}"
    assert math.isfinite(time_val) and time_val > 0.0, (
        f"Benchmark time must be a finite, positive duration, got {time_val}"
    )

    argument = b"100 * 50 + 20"
    for _ in range(100):
        evaluate(argument)
    start = time.perf_counter()
    for _ in range(10000):
        evaluate(argument)
    reference_time = time.perf_counter() - start

    lower = max(reference_time / 100.0, 1e-7)
    upper = max(reference_time * 100.0, 0.05)
    assert lower <= time_val <= upper, (
        f"Reported benchmark duration {time_val} is implausible for 10,000 FFI calls "
        f"(verifier measured {reference_time})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
