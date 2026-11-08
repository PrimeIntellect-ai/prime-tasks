#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "uptime_monitor.c")
STATE = os.path.join(HOME, "state.txt")
LOG = os.path.join(HOME, "fixed_variance.log")
SCRIPT = os.path.join(HOME, "regression_test.sh")
EXE = "/tmp/uptime_monitor_test"


def compile_monitor():
    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-lm", "-o", EXE],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to compile {SOURCE}:\n{result.stderr}"


def run_case(count, total, total_sq, new_latency):
    with open(STATE, "w") as f:
        f.write(f"{count} {total:.17g} {total_sq:.17g}\n")

    result = subprocess.run(
        [EXE, f"{new_latency:.17g}"], capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"Executable failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    output = result.stdout.strip()
    assert output and len(output.splitlines()) == 1, f"Unexpected output: {output!r}"
    try:
        value = float(output)
    except ValueError:
        raise AssertionError(f"Output is not numeric: {output!r}")
    assert math.isfinite(value), f"Output is not finite: {output!r}"
    return value


def test_fixed_variance_log():
    assert os.path.isfile(LOG), f"Log file {LOG} is missing."
    with open(LOG, "r") as f:
        content = f.read().strip()
    assert content == "0.000000", (
        f"Expected variance to be '0.000000', but got '{content}'."
    )


def test_regression_test_script():
    assert os.path.isfile(SCRIPT), f"Regression test script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Regression test script {SCRIPT} is not executable."

    with open(SCRIPT, "r", errors="replace") as f:
        script_text = f.read()
    assert re.search(r"\bgcc\b", script_text), "Regression test does not invoke gcc."
    assert "uptime_monitor.c" in script_text, "Regression test does not compile uptime_monitor.c."
    assert "state.txt" in script_text, "Regression test does not create/use state.txt."

    result = subprocess.run(["bash", SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Regression test script failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    # Mutation test: a genuine regression test must reject a compilable monitor
    # that emits NaN, rather than merely returning success unconditionally.
    with open(SOURCE, "rb") as f:
        original_source = f.read()
    original_mode = stat.S_IMODE(os.stat(SOURCE).st_mode)
    try:
        with open(SOURCE, "w") as f:
            f.write(
                '#include <stdio.h>\n'
                'int main(int argc, char **argv) { (void)argc; (void)argv; '
                'puts("NaN"); return 0; }\n'
            )
        bad_result = subprocess.run(["bash", SCRIPT], capture_output=True, text=True)
        assert bad_result.returncode != 0, (
            "Regression test incorrectly accepted a monitor that outputs NaN.\n"
            f"Stdout: {bad_result.stdout}\nStderr: {bad_result.stderr}"
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        os.chmod(SOURCE, original_mode)


def test_uptime_monitor_c_fixed_and_general():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    compile_monitor()

    # Preserve the original required bad-state assertion.
    with open(STATE, "w") as f:
        f.write("1000 1000000000.0 1000000000000000.0\n")
    result = subprocess.run([EXE, "1000000.0"], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Executable failed with exit code {result.returncode}.\nStderr: {result.stderr}"
    )
    output = result.stdout.strip()
    assert output != "NaN", "The C program still outputs 'NaN' for the bad state."
    assert output == "0.000000", f"Expected output to be '0.000000', but got '{output}'."

    # Exercise varied, unpredictable positive-variance states. Expected answers
    # are derived from the generated samples, so a constant-output program fails.
    rng = random.SystemRandom()
    for _ in range(10):
        count = rng.randint(2, 12)
        samples = [rng.uniform(1.0, 50000.0) for _ in range(count)]
        new_latency = rng.uniform(1.0, 50000.0)
        total = sum(samples)
        total_sq = sum(x * x for x in samples)
        updated = samples + [new_latency]
        mean = sum(updated) / len(updated)
        expected = math.sqrt(sum((x - mean) ** 2 for x in updated) / len(updated))
        actual = run_case(count, total, total_sq, new_latency)
        assert math.isclose(actual, expected, rel_tol=2e-6, abs_tol=2e-5), (
            f"Incorrect result for generated state: expected {expected:.6f}, got {actual:.6f}"
        )

    # Find an IEEE-754 cancellation case at verification time and ensure it is
    # handled without producing NaN or another non-finite result.
    cancellation_case = None
    for _ in range(20000):
        count = rng.randint(10, 10000)
        x = rng.uniform(1e8, 1e12)
        total = float(count * x)
        total_sq = float(count * x * x)
        new_latency = x
        n = count + 1
        s = total + new_latency
        ss = total_sq + new_latency * new_latency
        naive_variance = ss / n - (s / n) * (s / n)
        if naive_variance < 0.0:
            cancellation_case = (count, total, total_sq, new_latency)
            break
    assert cancellation_case is not None, "Could not construct a cancellation test case."
    actual = run_case(*cancellation_case)
    assert actual >= 0.0, f"Cancellation case produced an invalid result: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
