#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

TRACKER_DIR = "/home/user/uptime_tracker"
TRACKER_SRC = os.path.join(TRACKER_DIR, "tracker.c")
TRACKER_BIN = os.path.join(TRACKER_DIR, "tracker")
TRACE_PATH = "/home/user/trace.log"


def test_api_secret():
    secret_path = "/home/user/api_secret.txt"
    assert os.path.isfile(secret_path), f"{secret_path} is missing."
    with open(secret_path, "r") as f:
        content = f.read().strip()
    assert content == "sre-core-auth-992x-alpha", f"Incorrect secret in {secret_path}. Found: {content}"


def test_ping_count():
    count_path = "/home/user/ping_count.txt"
    assert os.path.isfile(count_path), f"{count_path} is missing."
    with open(count_path, "r") as f:
        content = f.read().strip()
    assert content == "15", f"Incorrect ping count in {count_path}. Expected 15, found: {content}"


def test_tracker_c_patched():
    tracker_path = "/home/user/uptime_tracker/tracker.c"
    assert os.path.isfile(tracker_path), f"{tracker_path} is missing."
    with open(tracker_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "i < WINDOW_SIZE" in content or "i<WINDOW_SIZE" in content or "i < 5" in content or "i<5" in content, \
        "The off-by-one bug in tracker.c does not appear to be fixed (expected loop condition to use < instead of <=)."
    assert "i <= WINDOW_SIZE" not in content and "i<=WINDOW_SIZE" not in content, \
        "The off-by-one bug (<=) is still present in tracker.c."


def test_compilation_and_execution():
    # Re-compile to ensure it compiles without error.
    compile_proc = subprocess.run(
        ["gcc", "-o", TRACKER_BIN, TRACKER_SRC],
        cwd=TRACKER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr.decode()}"

    # Do not trust a trace prepared before verification.
    try:
        os.remove(TRACE_PATH)
    except FileNotFoundError:
        pass

    # Run to ensure no segfaults and that the shipped program computes its result.
    run_proc = subprocess.run(
        [TRACKER_BIN],
        cwd=TRACKER_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert run_proc.returncode == 0, f"Execution failed (possible segfault or error):\n{run_proc.stderr.decode()}"
    assert run_proc.stdout.decode().strip() == "Average uptime: 98.52", \
        f"Incorrect program output: {run_proc.stdout.decode()!r}"


def test_trace_log():
    log_path = "/home/user/trace.log"
    assert os.path.isfile(log_path), f"{log_path} is missing. Did you run the compiled tracker?"
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Step 0 sum: 99.90",
        "Step 1 sum: 199.90",
        "Step 2 sum: 295.40",
        "Step 3 sum: 394.40",
        "Step 4 sum: 492.60"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {log_path} is incorrect. Expected '{expected}', found '{actual}'."


def test_rolling_average_and_trace_on_derived_inputs(tmp_path):
    # Include the submitted source in a harness so the requested function is
    # exercised directly on values not known until verification time.
    harness_src = tmp_path / "harness.c"
    harness_bin = tmp_path / "harness"
    harness_src.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#define main tracker_original_main
#include "/home/user/uptime_tracker/tracker.c"
#undef main

int main(int argc, char **argv) {
    if (argc != 6) return 90;
    float window[5];
    for (int i = 0; i < 5; i++) window[i] = strtof(argv[i + 1], NULL);
    float result = calculate_rolling_average(window);
    printf("RESULT %.2f\n", result);
    return 0;
}
''')

    compile_proc = subprocess.run(
        ["gcc", "-o", str(harness_bin), str(harness_src)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert compile_proc.returncode == 0, f"Function harness compilation failed:\n{compile_proc.stderr.decode()}"

    rng = secrets.SystemRandom()
    cases = [[rng.randint(1, 80) for _ in range(5)] for _ in range(2)]
    for values in cases:
        try:
            os.remove(TRACE_PATH)
        except FileNotFoundError:
            pass

        run_proc = subprocess.run(
            [str(harness_bin)] + [str(v) for v in values],
            cwd=TRACKER_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10
        )
        assert run_proc.returncode == 0, f"Function harness failed:\n{run_proc.stderr.decode()}"

        expected_average = sum(values) / 5.0
        assert run_proc.stdout.decode().strip() == f"RESULT {expected_average:.2f}", \
            f"Rolling average is incorrect for verifier-derived input {values}."

        assert os.path.isfile(TRACE_PATH), "calculate_rolling_average did not create the trace log."
        with open(TRACE_PATH, "r") as f:
            actual_lines = [line.rstrip("\n") for line in f if line.strip()]

        running = 0
        expected_lines = []
        for i, value in enumerate(values):
            running += value
            expected_lines.append(f"Step {i} sum: {running:.2f}")

        assert actual_lines == expected_lines, \
            f"Incorrect trace for verifier-derived input {values}: {actual_lines!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
