#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from decimal import Decimal

SCRIPT = "/home/user/analyze_metrics.sh"
DATA = "/home/user/query_results.log"
OUTPUT = "/home/user/final_metric.txt"


def run_script(timeout=10):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT), (
        f"File {OUTPUT} is missing. The script did not run successfully or output "
        "to the correct location."
    )
    content = open(OUTPUT, "r").read().strip()
    try:
        value = Decimal(content)
    except Exception:
        raise AssertionError(f"Content of {OUTPUT} is not a valid float: {content!r}")
    assert value.is_finite(), f"Content of {OUTPUT} is not a finite float: {content!r}"
    return value


def bc(expression):
    result = subprocess.run(
        ["bc", "-l"],
        input=f"scale=3; {expression}\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    value = result.stdout.strip()
    assert value, f"Reference bc calculation failed for {expression!r}"
    return value


def reference_estimate(values):
    estimate = "10.000"
    delta = "1.000"
    threshold = "0.010"
    for _ in range(1000):
        if bc(f"{delta} > {threshold}") != "1":
            return Decimal(estimate)
        total = "0"
        for value in values:
            diff = bc(f"({value} - {estimate}) / 2")
            total = bc(f"{total} + {diff}")
        avg_diff = bc(f"{total} / {len(values)}")
        new_estimate = bc(f"{estimate} + {avg_diff}")
        delta = bc(f"{new_estimate} - {estimate}")
        if bc(f"{delta} < 0") == "1":
            delta = bc(f"{delta} * -1")
        estimate = new_estimate
    raise AssertionError("Reference convergence calculation did not terminate")


def encoded_log(values):
    return (
        f"[INFO] Query returned: val={values[0]}\n"
        f"[INFO] Query returned: val={values[1]}, status=OK\n"
        f"[WARN] Query timeout\n"
        f"[INFO] Query returned: val={values[2]}\r\n"
        f"[INFO] Query returned: val={values[3]},source=cache\r\n"
        f"[INFO] Query returned: val={values[4]} trailing metadata\n"
        f"[INFO] Query returned: val={values[5]}, status=VALID\n"
    ).encode()


def test_analyze_metrics_script_executable():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"File {SCRIPT} is no longer executable."


def test_script_runs_parses_all_values_and_converges():
    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        # Preserve the original final-state assertion, but produce the file by
        # actually executing the submitted artifact.
        original_value = run_script()
        assert Decimal("15.0") <= original_value <= Decimal("15.2"), (
            f"Expected final metric to be approximately 15.1, but got {original_value}"
        )

        # Exercise unseen values in every edge-case format. The expected result
        # is independently derived with the specified iterative bc formula.
        rng = random.SystemRandom()
        for _ in range(2):
            values = [f"{rng.randint(11000, 29000) / 1000:.3f}" for _ in range(6)]
            with open(DATA, "wb") as f:
                f.write(encoded_log(values))
            expected = reference_estimate(values)
            actual = run_script()
            assert actual == expected, (
                f"Incorrect convergence result for parsed values {values}: "
                f"expected {expected}, got {actual}"
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)

    # Leave the requested artifact in its normal final state.
    final_value = run_script()
    assert Decimal("15.0") <= final_value <= Decimal("15.2"), (
        f"Expected final metric to be approximately 15.1, but got {final_value}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
