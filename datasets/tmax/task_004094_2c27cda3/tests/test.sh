#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile
import time

import pytest

ORACLE_PATH = "/app/integrator_oracle"
FAST_INTEGRATOR_PATH = "/home/user/fast_integrator"
SOURCE_PATH = "/home/user/integrator.c"
SCRIPT_PATH = "/home/user/test_regression.sh"


def run_binary(binary_path, guess, target_c):
    start_time = time.perf_counter()
    result = subprocess.run(
        [binary_path, str(guess), str(target_c)],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )
    elapsed = time.perf_counter() - start_time
    fields = result.stdout.strip().split()
    assert fields, f"No numeric output from {binary_path}"
    try:
        value = float(fields[-1])
    except ValueError:
        pytest.fail(f"Could not parse output from {binary_path}: {result.stdout!r}")
    assert math.isfinite(value), f"Non-finite output from {binary_path}: {value}"
    return value, elapsed


def test_final_state():
    # Preserve the original existence and executability assertions.
    assert os.path.exists(FAST_INTEGRATOR_PATH), f"Optimized executable not found at {FAST_INTEGRATOR_PATH}"
    assert os.access(FAST_INTEGRATOR_PATH, os.X_OK), f"File at {FAST_INTEGRATOR_PATH} is not executable"
    assert os.path.exists(SCRIPT_PATH), f"Bash script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Bash script at {SCRIPT_PATH} is not executable"
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"^\s*#\s*pragma\s+omp\s+parallel\b", source_without_comments, re.M), \
        "integrator.c does not contain an active OpenMP parallel pragma"

    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        script_text = f.read()
    assert "-O3" in script_text, "Regression script does not compile with -O3"
    assert "-fopenmp" in script_text, "Regression script does not compile with -fopenmp"
    assert "integrator_oracle" in script_text, "Regression script does not reference the oracle"
    assert "fast_integrator" in script_text, "Regression script does not reference the optimized program"
    assert re.search(r"bootstrap|resampl", script_text, re.I), \
        "Regression script contains no bootstrap/resampling implementation"

    # Independently compile the submitted C source using the required flags.
    rebuilt_fd, rebuilt_path = tempfile.mkstemp(prefix="rebuilt_integrator_", dir="/tmp")
    os.close(rebuilt_fd)
    os.unlink(rebuilt_path)
    subprocess.run(
        ["gcc", "-O3", "-fopenmp", SOURCE_PATH, "-lm", "-o", rebuilt_path],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    assert os.access(rebuilt_path, os.X_OK)

    # Execute the regression script. Wrap the oracle temporarily so its actual
    # invocations and inputs can be counted rather than trusting script text.
    invocation_log = "/tmp/regression_oracle_invocations.log"
    real_oracle = f"/app/.integrator_oracle.real.{os.getpid()}"
    if os.path.exists(invocation_log):
        os.unlink(invocation_log)
    before_mtime = os.stat(FAST_INTEGRATOR_PATH).st_mtime_ns
    time.sleep(0.05)
    os.replace(ORACLE_PATH, real_oracle)
    try:
        wrapper = f'''#!/bin/bash
printf '%s\\t%s\\n' "$1" "$2" >> {invocation_log}
exec {real_oracle} "$@"
'''
        with open(ORACLE_PATH, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(ORACLE_PATH, 0o755)

        regression = subprocess.run(
            ["bash", SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=300,
        )
    finally:
        if os.path.exists(ORACLE_PATH):
            os.unlink(ORACLE_PATH)
        os.replace(real_oracle, ORACLE_PATH)

    assert regression.returncode == 0, \
        f"Regression script failed:\nstdout={regression.stdout}\nstderr={regression.stderr}"
    output_lines = [line.strip() for line in regression.stdout.splitlines() if line.strip()]
    assert len(output_lines) == 1, \
        f"Regression script must output exactly one non-empty line, got: {regression.stdout!r}"
    try:
        lower_bound = float(output_lines[0])
    except ValueError:
        pytest.fail(f"Regression script output is not a number: {output_lines[0]!r}")
    assert math.isfinite(lower_bound), "Regression script produced a non-finite confidence bound"
    assert lower_bound >= 2.0, f"Reported lower confidence bound {lower_bound} is below 2.0"

    assert os.path.exists(invocation_log), "Regression script did not execute the oracle"
    with open(invocation_log, "r", encoding="utf-8", errors="replace") as f:
        calls = [line.strip().split("\t") for line in f if line.strip()]
    assert len(calls) >= 100, f"Regression script made only {len(calls)} oracle calls; at least 100 are required"
    valid_inputs = set()
    for call in calls:
        assert len(call) == 2, f"Malformed oracle invocation recorded: {call!r}"
        guess, target = map(float, call)
        assert math.isfinite(guess) and math.isfinite(target), "Regression script used non-finite inputs"
        valid_inputs.add((guess, target))
    assert len(valid_inputs) >= 80, "Regression trials do not contain sufficiently varied random inputs"

    assert os.stat(FAST_INTEGRATOR_PATH).st_mtime_ns > before_mtime, \
        "Regression script did not rebuild /home/user/fast_integrator"
    with open(FAST_INTEGRATOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_integrator is not a compiled ELF executable"
    with open(FAST_INTEGRATOR_PATH, "rb") as f1, open(ORACLE_PATH, "rb") as f2:
        assert f1.read() != f2.read(), "fast_integrator is byte-identical to the oracle"

    # Exercise the independently rebuilt source on verifier-selected inputs.
    hidden_rng = random.SystemRandom()
    hidden_cases = [(hidden_rng.uniform(0.5, 1.5), hidden_rng.uniform(0.1, 0.8)) for _ in range(8)]
    for guess, target in hidden_cases:
        oracle_val, _ = run_binary(ORACLE_PATH, guess, target)
        rebuilt_val, _ = run_binary(rebuilt_path, guess, target)
        assert abs(oracle_val - rebuilt_val) <= 1e-6, \
            f"Rebuilt integrator error exceeds 1e-6 for guess={guess}, C={target}"

    # Preserve the original 50-trial accuracy and average-speedup assertions,
    # while explicitly rejecting NaN and infinity in run_binary above.
    random.seed(42)
    num_trials = 50
    oracle_times = []
    fast_times = []
    max_error = 0.0
    for _ in range(num_trials):
        guess = random.uniform(0.5, 1.5)
        target_c = random.uniform(0.1, 0.8)
        oracle_val, oracle_time = run_binary(ORACLE_PATH, guess, target_c)
        fast_val, fast_time = run_binary(FAST_INTEGRATOR_PATH, guess, target_c)
        oracle_times.append(oracle_time)
        fast_times.append(fast_time)
        error = abs(oracle_val - fast_val)
        assert math.isfinite(error), "Accuracy error is non-finite"
        if error > max_error:
            max_error = error

    mean_oracle_time = sum(oracle_times) / num_trials
    mean_fast_time = sum(fast_times) / num_trials
    speedup = mean_oracle_time / mean_fast_time if mean_fast_time > 0 else float("inf")
    assert max_error <= 1e-6, f"Maximum L_infinity error {max_error} exceeds threshold 1e-6"
    assert speedup >= 2.0, \
        f"Speedup {speedup:.2f}x is below the 2.0x threshold (Oracle: {mean_oracle_time:.4f}s, Fast: {mean_fast_time:.4f}s)"

    os.unlink(rebuilt_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
