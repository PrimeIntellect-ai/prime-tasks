#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import math
import os
import random
import re
import subprocess
import tempfile
import time

import pytest

LOG_PATH = "/home/user/telemetry.log"
CPP_PATH = "/home/user/repo/analyzer.cpp"
NUMBER_RE = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


def parse_only_float(stdout):
    output = stdout.strip()
    assert output, "Analyzer produced no output."
    assert NUMBER_RE.fullmatch(output), f"Analyzer output {output!r} is not only a floating-point number."
    value = float(output)
    assert math.isfinite(value), f"Analyzer output {output!r} is not finite."
    return value


def cpu_cents(token):
    whole, fraction = token.split(b".", 1)
    fraction = (fraction + b"00")[:2]
    return int(whole) * 100 + int(fraction)


@functools.lru_cache(maxsize=1)
def telemetry_averages():
    totals = {}
    counts = {}
    with open(LOG_PATH, "rb") as log_file:
        for line_number, line in enumerate(log_file, 1):
            fields = line.split()
            assert len(fields) == 4, f"Malformed telemetry line {line_number}."
            vm_id = fields[1].decode("ascii")
            try:
                cents = cpu_cents(fields[2])
            except Exception as exc:
                raise AssertionError(f"Malformed CPU value on telemetry line {line_number}.") from exc
            totals[vm_id] = totals.get(vm_id, 0) + cents
            counts[vm_id] = counts.get(vm_id, 0) + 1
    return {vm_id: totals[vm_id] / counts[vm_id] / 100.0 for vm_id in totals}


def compile_analyzer(binary_path):
    proc = subprocess.run(
        ["g++", "-O3", CPP_PATH, "-o", binary_path],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"Failed to compile {CPP_PATH}:\n{proc.stderr}"


def test_telemetry_log_exists():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist. Did you run the telemetry generator?"
    size = os.path.getsize(LOG_PATH)
    assert size > 50_000_000, f"Log file {LOG_PATH} is too small ({size} bytes). Did you redirect the full output?"


def test_telemetry_log_is_generator_output():
    generator = subprocess.Popen(["/app/qemu_telem_gen"], stdout=subprocess.PIPE)
    mismatch = None
    try:
        with open(LOG_PATH, "rb") as actual:
            while True:
                expected_chunk = generator.stdout.read(1024 * 1024)
                if not expected_chunk:
                    if actual.read(1):
                        mismatch = "Telemetry log has extra data after the generator output."
                    break
                actual_chunk = actual.read(len(expected_chunk))
                if actual_chunk != expected_chunk:
                    mismatch = "Telemetry log does not match the output of /app/qemu_telem_gen."
                    break
        if mismatch is not None:
            generator.kill()
        return_code = generator.wait()
    finally:
        if generator.poll() is None:
            generator.kill()
            generator.wait()
    assert mismatch is None, mismatch
    assert return_code == 0, "Telemetry generator failed while validating telemetry.log."


def test_code_committed():
    repo_path = "/home/user/repo"
    assert os.path.isfile(CPP_PATH), f"Source file {CPP_PATH} does not exist."

    proc = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, "Failed to run git ls-tree. Is there a valid commit?"
    assert "analyzer.cpp" in proc.stdout.splitlines(), "analyzer.cpp is not committed to the repository."

    committed = subprocess.run(
        ["git", "show", "HEAD:analyzer.cpp"],
        cwd=repo_path,
        capture_output=True,
    )
    assert committed.returncode == 0, "Failed to read committed analyzer.cpp."
    with open(CPP_PATH, "rb") as source_file:
        working_tree = source_file.read()
    assert working_tree == committed.stdout, "The working-tree analyzer.cpp differs from the committed version."


def test_analyzer_performance_and_correctness():
    bin_path = "/tmp/analyzer_perf"
    compile_analyzer(bin_path)

    start_time = time.monotonic()
    run_proc = subprocess.run(
        [bin_path, LOG_PATH, "vm-42"],
        capture_output=True,
        text=True,
    )
    elapsed = time.monotonic() - start_time

    assert run_proc.returncode == 0, f"Analyzer crashed or returned non-zero exit code:\n{run_proc.stderr}"
    avg_cpu = parse_only_float(run_proc.stdout)

    # Preserve the original broad sanity assertion and additionally verify the
    # actual average derived from the submitted telemetry file.
    assert 40.0 <= avg_cpu <= 60.0, f"Calculated average CPU ({avg_cpu}) seems incorrect. Expected ~50.0"
    expected = telemetry_averages()["vm-42"]
    assert abs(avg_cpu - expected) <= 0.001, f"Incorrect average for vm-42: expected {expected:.8f}, got {avg_cpu}"

    threshold = 0.15
    assert elapsed <= threshold, f"Execution too slow: {elapsed:.4f}s (Must be <= {threshold}s). Optimize your I/O and parsing."


def test_analyzer_on_unpredictable_vm_queries():
    bin_path = "/tmp/analyzer_random_queries"
    compile_analyzer(bin_path)
    averages = telemetry_averages()
    vm_ids = random.SystemRandom().sample(sorted(averages), 3)

    for vm_id in vm_ids:
        run_proc = subprocess.run(
            [bin_path, LOG_PATH, vm_id],
            capture_output=True,
            text=True,
        )
        assert run_proc.returncode == 0, f"Analyzer failed for {vm_id}:\n{run_proc.stderr}"
        actual = parse_only_float(run_proc.stdout)
        expected = averages[vm_id]
        assert abs(actual - expected) <= 0.001, f"Incorrect average for {vm_id}: expected {expected:.8f}, got {actual}"


def test_analyzer_parses_runtime_generated_input():
    bin_path = "/tmp/analyzer_synthetic"
    compile_analyzer(bin_path)
    rng = random.SystemRandom()
    target = f"vm-{rng.randrange(100)}"
    rows = []
    target_values = []

    for index in range(600):
        vm_id = target if index < 80 else f"vm-{rng.randrange(100)}"
        cents = rng.randrange(0, 10000)
        if vm_id == target:
            target_values.append(cents)
        rows.append(f"[{1800000000 + index}] {vm_id} {cents // 100}.{cents % 100:02d} {rng.randrange(8192)}.00\n")
    rng.shuffle(rows)

    with tempfile.NamedTemporaryFile(mode="w", prefix="telemetry-runtime-", delete=False) as test_log:
        test_log.writelines(rows)
        test_log_path = test_log.name
    try:
        run_proc = subprocess.run(
            [bin_path, test_log_path, target],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(test_log_path)

    assert run_proc.returncode == 0, f"Analyzer failed on generated input:\n{run_proc.stderr}"
    actual = parse_only_float(run_proc.stdout)
    expected = sum(target_values) / len(target_values) / 100.0
    assert abs(actual - expected) <= 0.001, f"Incorrect average on generated input: expected {expected:.8f}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
