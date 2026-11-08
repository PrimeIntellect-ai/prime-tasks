#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess

SOURCE = "/home/user/aggregator.go"
METRICS = "/home/user/container_metrics.log"
RESULT = "/home/user/result.txt"
BINARY = "/tmp/aggregator_submission"


def run_program():
    try:
        os.remove(RESULT)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Fixed aggregator exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT), f"Missing file: {RESULT}. Did you run the fixed Go program?"

    with open(RESULT, "rb") as f:
        raw = f.read()
    assert re.fullmatch(rb"[0-9]+\.[0-9]{6}\n?", raw), (
        f"{RESULT} must contain only a number formatted to exactly 6 decimal places"
    )
    return raw.decode("ascii").strip()


def test_submission():
    assert os.path.isfile(SOURCE), f"Missing Go source file: {SOURCE}"
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"Expected {SOURCE} to be a regular file"
    assert os.path.getsize(SOURCE) > 0, f"Go source file is empty: {SOURCE}"

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"aggregator.go does not compile: {build.stderr}"

    with open(METRICS, "rb") as f:
        original_metrics = f.read()

    rng = random.SystemRandom()
    try:
        # Exercise the compiled submission on unpredictable high-baseline inputs.
        # Multiples of 1/64 are exactly representable, so expected population
        # variances can be derived independently without decimal parsing error.
        for _ in range(3):
            offsets = []
            for _ in range(rng.randrange(7, 13)):
                k = rng.randrange(1, 25)
                offsets.extend((k, -k))
            offsets.append(0)
            rng.shuffle(offsets)

            values = [100000000.0 + k / 64.0 for k in offsets]
            with open(METRICS, "w", encoding="ascii") as f:
                for value in values:
                    f.write(f"{value:.9f}\n")

            mean = math.fsum(values) / len(values)
            variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
            expected = f"{math.sqrt(variance):.6f}"
            actual = run_program()
            assert actual == expected, (
                f"Incorrect population standard deviation for generated metrics: "
                f"expected {expected}, got {actual}"
            )

        # Restore and run the ticket's actual input. Preserve the original exact
        # result assertion and leave result.txt containing the requested answer.
        with open(METRICS, "wb") as f:
            f.write(original_metrics)
        content = run_program()
        expected_output = "0.014142"
        assert content == expected_output, (
            f"Expected standard deviation '{expected_output}' in {RESULT}, but got '{content}'"
        )
    finally:
        with open(METRICS, "wb") as f:
            f.write(original_metrics)

PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
