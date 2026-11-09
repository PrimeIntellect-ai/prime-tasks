#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import tempfile
import time

import numpy as np
import pytest
from scipy import stats


def run_and_time(cmd, timeout=180):
    start = time.perf_counter()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, check=True, timeout=timeout)
    return res.stdout, time.perf_counter() - start


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Required file not found: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} must be a compiled executable"


def test_fast_search_speedup_and_accuracy():
    fast_search = "/home/user/fast_search"
    fast_source = "/home/user/fast_search.cpp"
    ref_search = "/app/ref_search"
    dataset = "/home/user/dataset.bin"
    queries = "/home/user/queries.bin"

    assert os.path.isfile(fast_source), f"fast_search.cpp not found at {fast_source}"
    assert_elf_executable(fast_search)

    # Preserve the original public-data correctness and speed assertions.
    ref_out, ref_time = run_and_time([ref_search, dataset, queries])
    fast_out, fast_time = run_and_time([fast_search, dataset, queries])
    assert ref_out.strip() == fast_out.strip(), \
        "Output of fast_search does not match ref_search exactly."
    speedup = ref_time / fast_time
    assert speedup >= 5.0, \
        f"Speedup {speedup:.2f} is less than the required threshold of 5.0."

    # Generate an unpredictable hold-out with the promised dimensions after the
    # agent has finished, so output captured from the public files cannot pass.
    with tempfile.TemporaryDirectory(prefix="search_holdout_") as td:
        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
        hold_dataset = os.path.join(td, "dataset.bin")
        hold_queries = os.path.join(td, "queries.bin")
        rng.standard_normal((10000, 128), dtype=np.float32).tofile(hold_dataset)
        rng.standard_normal((100, 128), dtype=np.float32).tofile(hold_queries)

        ref_out, ref_time = run_and_time([ref_search, hold_dataset, hold_queries])
        fast_out, fast_time = run_and_time([fast_search, hold_dataset, hold_queries])
        assert ref_out.strip() == fast_out.strip(), \
            "Output of fast_search does not match ref_search on the secret hold-out."
        speedup = ref_time / fast_time
        assert speedup >= 5.0, \
            f"Hold-out speedup {speedup:.2f} is less than the required threshold of 5.0."


def _make_wrapper(path, real_path, log_path, delay):
    code = f'''#!/usr/bin/python3
import subprocess, sys, time
start = time.perf_counter()
time.sleep({delay!r})
r = subprocess.run([{real_path!r}] + sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
elapsed = time.perf_counter() - start
with open({log_path!r}, "a") as f:
    f.write(str(elapsed) + "\\n")
sys.stdout.buffer.write(r.stdout)
sys.stderr.buffer.write(r.stderr)
sys.exit(r.returncode)
'''
    with open(path, "w") as f:
        f.write(code)
    os.chmod(path, 0o755)


def test_benchmark_script_and_ci_txt():
    benchmark_script = "/home/user/benchmark.py"
    ci_txt = "/home/user/ci.txt"
    fast = "/home/user/fast_search"
    ref = "/app/ref_search"

    # Preserve the original existence assertions, then require the script to
    # regenerate ci.txt itself.
    assert os.path.isfile(benchmark_script), \
        f"benchmark.py not found at {benchmark_script}"
    assert os.path.exists(ci_txt), f"ci.txt not found at {ci_txt}"

    token = secrets.token_hex(12)
    real_fast = f"/tmp/fast_search.real.{token}"
    real_ref = f"/tmp/ref_search.real.{token}"
    fast_log = f"/tmp/fast_search.calls.{token}"
    ref_log = f"/tmp/ref_search.calls.{token}"
    ref_delay = 0.08 + secrets.randbelow(50000) / 1000000.0
    fast_delay = 0.015 + secrets.randbelow(15000) / 1000000.0

    os.replace(fast, real_fast)
    os.replace(ref, real_ref)
    try:
        _make_wrapper(fast, real_fast, fast_log, fast_delay)
        _make_wrapper(ref, real_ref, ref_log, ref_delay)
        os.remove(ci_txt)

        subprocess.run(["python3", benchmark_script], cwd="/home/user",
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       text=True, check=True, timeout=300)

        assert os.path.isfile(ci_txt), "benchmark.py did not recreate ci.txt"
        with open(ref_log) as f:
            ref_times = [float(x) for x in f if x.strip()]
        with open(fast_log) as f:
            fast_times = [float(x) for x in f if x.strip()]

        assert len(ref_times) == 15, \
            f"benchmark.py must run /app/ref_search exactly 15 times; observed {len(ref_times)}"
        assert len(fast_times) == 15, \
            f"benchmark.py must run fast_search exactly 15 times; observed {len(fast_times)}"

        with open(ci_txt, "r") as f:
            content = f.read().strip()
        parts = content.split(',')
        assert len(parts) == 2, \
            f"ci.txt must contain exactly two comma-separated floats. Found: {content}"
        try:
            lower = float(parts[0].strip())
            upper = float(parts[1].strip())
        except ValueError:
            pytest.fail(f"ci.txt contents are not valid floats. Found: {content}")

        assert math.isfinite(lower) and math.isfinite(upper), \
            "ci.txt bounds must be finite floats"
        assert lower <= upper, \
            f"Lower bound ({lower}) of CI must be less than or equal to upper bound ({upper})."

        ratios = np.asarray(ref_times) / np.asarray(fast_times)
        mean = float(np.mean(ratios))
        sem = float(stats.sem(ratios))
        if sem == 0.0:
            expected_lower = expected_upper = mean
        else:
            expected_lower, expected_upper = stats.t.interval(
                0.95, len(ratios) - 1, loc=mean, scale=sem)

        # Allow ordinary timer and implementation-method variation while
        # rejecting stale or fabricated values unrelated to the observed runs.
        tolerance = max(0.25, 0.30 * mean)
        assert abs(lower - expected_lower) <= tolerance, \
            f"Reported lower CI bound {lower} is inconsistent with benchmark timings"
        assert abs(upper - expected_upper) <= tolerance, \
            f"Reported upper CI bound {upper} is inconsistent with benchmark timings"
    finally:
        for wrapper, real in ((fast, real_fast), (ref, real_ref)):
            try:
                if os.path.lexists(wrapper):
                    os.remove(wrapper)
            finally:
                if os.path.exists(real):
                    os.replace(real, wrapper)
        for path in (fast_log, ref_log):
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
