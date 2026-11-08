#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import time
import pytest


def test_generate_row_exists_and_executable():
    path = "/home/user/generate_row.sh"
    assert os.path.isfile(path), f"The script {path} is missing."
    assert os.access(path, os.X_OK), f"The script {path} is not executable."


def test_benchmark_script_exists_and_executable():
    path = "/home/user/benchmark.sh"
    assert os.path.isfile(path), f"The script {path} is missing."
    assert os.access(path, os.X_OK), f"The script {path} is not executable."


def test_benchmark_log_exists_and_valid():
    log_path = "/home/user/benchmark.log"
    assert os.path.isfile(log_path), f"The log file {log_path} is missing. Did you run the benchmark script?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content, f"The log file {log_path} is empty."

    try:
        val = float(content)
        assert val >= 0, f"Benchmark time must be non-negative, got {val}."
        assert math.isfinite(val), f"Benchmark time must be finite, got {val}."
    except ValueError:
        pytest.fail(f"Content of {log_path} is not a valid float: {content}")


def test_fuzz_equivalence():
    oracle = "/tests/oracle_generate_row.sh"
    agent = "/home/user/generate_row.sh"

    assert os.path.isfile(oracle), f"Oracle script missing at {oracle}."
    assert os.access(oracle, os.X_OK), f"Oracle script at {oracle} is not executable."

    with open(oracle, "rb") as f:
        oracle_bytes = f.read()
    with open(agent, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Submission must not be byte-identical to the reference implementation."

    random.seed(42)
    inputs = [random.randint(0, 9) for _ in range(10)]

    for t in inputs:
        oracle_res = subprocess.run([oracle, str(t)], capture_output=True, text=True)
        agent_res = subprocess.run([agent, str(t)], capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on input {t}: {oracle_res.stderr}"
        assert agent_res.returncode == 0, f"Agent script failed on input {t}: {agent_res.stderr}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on input T={t}.\n"
            f"Expected (Oracle): '{oracle_out}'\n"
            f"Got (Agent): '{agent_out}'"
        )


def test_benchmark_executes_all_six_runs_and_times_them():
    generator = "/home/user/generate_row.sh"
    saved = "/home/user/generate_row.sh.verifier_saved"
    benchmark = "/home/user/benchmark.sh"
    call_log = "/tmp/benchmark_calls"
    overlap_log = "/tmp/benchmark_overlap"
    lock_dir = "/tmp/benchmark_probe_lock"
    delay = 0.12

    for path in (call_log, overlap_log):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    try:
        os.rmdir(lock_dir)
    except FileNotFoundError:
        pass

    os.replace(generator, saved)
    try:
        probe = f'''#!/bin/bash
printf '%s\\n' "$#:$1" >> {call_log}
if ! mkdir {lock_dir} 2>/dev/null; then
    echo overlap >> {overlap_log}
else
    trap 'rmdir {lock_dir} 2>/dev/null || true' EXIT
fi
sleep {delay}
echo BENCHMARK_PROBE_OUTPUT
'''
        with open(generator, "w") as f:
            f.write(probe)
        os.chmod(generator, 0o755)

        started = time.monotonic()
        result = subprocess.run([benchmark], capture_output=True, text=True, timeout=15)
        elapsed = time.monotonic() - started

        assert result.returncode == 0, f"benchmark.sh failed: {result.stderr}"
        assert result.stdout == "", "benchmark.sh did not discard generate_row.sh standard output."
        assert not os.path.exists(overlap_log), "generate_row.sh runs were not sequential."

        with open(call_log, "r") as f:
            calls = f.read().splitlines()
        assert calls == [f"1:{t}" for t in range(6)], (
            "benchmark.sh must invoke generate_row.sh exactly once for each T from 0 through 5 in order."
        )

        with open("/home/user/benchmark.log", "r") as f:
            raw = f.read().strip()
        assert raw and len(raw.splitlines()) == 1, "benchmark.log must contain only one execution-time value."
        try:
            reported = float(raw)
        except ValueError:
            pytest.fail(f"benchmark.log is not a valid float: {raw}")
        assert math.isfinite(reported) and reported >= 0, "Benchmark time must be a finite non-negative float."
        assert reported >= delay * 6 * 0.75, "Reported time does not include all six instrumented runs."
        assert abs(reported - elapsed) <= 0.40, (
            f"Reported wall-clock time {reported} is inconsistent with observed time {elapsed:.3f}."
        )
    finally:
        try:
            os.remove(generator)
        except FileNotFoundError:
            pass
        os.replace(saved, generator)
        try:
            os.rmdir(lock_dir)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
