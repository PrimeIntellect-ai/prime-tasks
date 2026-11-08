#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess

PROFILER = "/home/user/profiler.go"
METRICS = "/home/user/metrics.csv"
OUTPUT = "/home/user/best_model.json"


def run_profiler():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ["go", "run", PROFILER],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."

    try:
        with open(OUTPUT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        assert False, f"File {OUTPUT} does not contain valid JSON: {exc}"

    assert "hypothesis" in data, f"Key 'hypothesis' is missing from {OUTPUT}."
    assert set(data) == {"hypothesis"}, f"{OUTPUT} must contain only the hypothesis field."
    assert data["hypothesis"] in ("A", "B"), "Hypothesis must be either A or B."
    return data["hypothesis"]


def gd_loss(rows, quadratic):
    w1 = 0.0
    w2 = 0.0
    previous = math.inf
    n = float(len(rows))

    for _ in range(50000):
        total = 0.0
        grad1 = 0.0
        grad2 = 0.0
        for cpu, mem, latency in rows:
            x1 = cpu * cpu if quadratic else cpu
            error = w1 * x1 + w2 * mem - latency
            total += error * error
            grad1 += error * x1
            grad2 += error * mem
        mse = total / n
        if abs(previous - mse) < 1e-5:
            break
        w1 -= 0.0005 * (2.0 / n) * grad1
        w2 -= 0.0005 * (2.0 / n) * grad2
        previous = mse

    return sum(
        (w1 * (cpu * cpu if quadratic else cpu) + w2 * mem - latency) ** 2
        for cpu, mem, latency in rows
    ) / n


def expected_winner(rows):
    loss_a = gd_loss(rows, False)
    loss_b = gd_loss(rows, True)
    return "A" if loss_a < loss_b else "B"


def write_metrics(rows):
    with open(METRICS, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["cpu", "mem", "latency"])
        writer.writerows(rows)


def make_case(family, rng):
    # Values are deliberately kept small enough for both specified gradient
    # descents to remain numerically stable.
    for _ in range(200):
        a = rng.uniform(0.5, 2.0)
        b = rng.uniform(0.4, 1.7)
        rows = []
        for _ in range(8):
            cpu = rng.uniform(0.35, 2.3)
            mem = rng.uniform(0.3, 2.6)
            latency = a * (cpu if family == "A" else cpu * cpu) + b * mem
            rows.append((round(cpu, 10), round(mem, 10), round(latency, 10)))
        if expected_winner(rows) == family:
            return rows
    raise AssertionError(f"Could not construct a stable {family} test case")


def test_profiler_go_exists():
    file_path = "/home/user/profiler.go"
    assert os.path.isfile(file_path), f"Expected Go program {file_path} does not exist."


def test_best_model_json_exists_and_correct_after_execution():
    # Preserve the original assertion, but require the submitted artifact to
    # actually generate the file rather than accepting a prewritten answer.
    hypothesis = run_profiler()
    assert hypothesis == "B", f"Expected hypothesis 'B', but got '{hypothesis}'."


def test_program_parses_fresh_data_and_computes_the_winner():
    with open(METRICS, "rb") as f:
        original_metrics = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    families = ["A", "A", "B", "B"]
    rng.shuffle(families)

    try:
        for family in families:
            rows = make_case(family, rng)
            expected = expected_winner(rows)
            write_metrics(rows)
            actual = run_profiler()
            assert actual == expected, (
                f"For freshly generated metrics, expected hypothesis {expected} "
                f"but program produced {actual}."
            )
    finally:
        with open(METRICS, "wb") as f:
            f.write(original_metrics)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
