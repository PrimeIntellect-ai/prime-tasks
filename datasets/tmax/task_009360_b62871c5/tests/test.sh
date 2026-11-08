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

import pytest

PIPELINE = "/home/user/pipeline"
DATA = "/home/user/data.csv"
OUTPUT = "/home/user/pipeline/cleaned.csv"
EXPECTED_ORIGINAL = [
    "F1,F2,Target",
    "1.0,2.5,0.0",
    "2.0,8.1,1.0",
    "3.0,3.2,0.0",
    "4.0,9.5,1.0",
    "5.0,1.2,0.0",
]


def read_output_lines():
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f.read().strip().split("\n")]


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["GOPATH"] = "/home/user/go"
    env["GOCACHE"] = "/home/user/.cache/go-build"
    os.makedirs(env["GOPATH"], exist_ok=True)
    os.makedirs(env["GOCACHE"], exist_ok=True)

    result = subprocess.run(
        ["go", "run", "."],
        cwd=PIPELINE,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, f"Go program failed:\n{result.stdout}"
    assert os.path.isfile(OUTPUT), "Go program did not generate cleaned.csv"


def pearson(a, b):
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    numerator = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    da = math.sqrt(sum((x - ma) ** 2 for x in a))
    db = math.sqrt(sum((y - mb) ** 2 for y in b))
    return numerator / (da * db)


def expected_cleaned(headers, rows):
    feature_count = len(headers) - 1
    dropped = set()
    for i in range(feature_count):
        for j in range(i + 1, feature_count):
            if abs(pearson([r[i] for r in rows], [r[j] for r in rows])) >= 0.90:
                dropped.add(j)

    retained = [i for i in range(feature_count) if i not in dropped]
    indices = retained + [feature_count]
    result = [",".join(headers[i] for i in indices)]
    result.extend(",".join(f"{row[i]:.1f}" for i in indices) for row in rows)
    return result


def test_etl_source_and_module_exist():
    source = os.path.join(PIPELINE, "etl.go")
    module = os.path.join(PIPELINE, "go.mod")
    assert os.path.lexists(source) and stat.S_ISREG(os.lstat(source).st_mode), \
        f"{source} must be a regular file"
    assert os.path.lexists(module) and stat.S_ISREG(os.lstat(module).st_mode), \
        f"{module} must be a regular file"

    with open(module, "r") as f:
        module_text = f.read()
    assert re.search(r"(?m)^\s*module\s+etl\s*$", module_text), \
        "go.mod must declare module etl"


def test_cleaned_csv_exists():
    """Check that the cleaned.csv file has been generated."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."


def test_cleaned_csv_content():
    """Verify the content of cleaned.csv matches the expected output."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    actual_content = read_output_lines()
    assert actual_content == EXPECTED_ORIGINAL, (
        f"The content of {OUTPUT} does not match the expected output. "
        f"Expected:\n{EXPECTED_ORIGINAL}\nActual:\n{actual_content}"
    )


def test_program_execution_and_general_correlation_behavior():
    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        # First prove that the submitted Go program itself reproduces the required
        # result for the supplied dataset, rather than trusting a prewritten CSV.
        run_program()
        assert read_output_lines() == EXPECTED_ORIGINAL

        # Build a fresh dataset at verification time. F3 is perfectly negatively
        # correlated with F1, F4 is perfectly correlated with F2, and Target is
        # correlated with F1 but must never participate in feature elimination.
        rng = random.SystemRandom()
        while True:
            f1 = [x / 10.0 for x in rng.sample(range(10, 100), 9)]
            f2 = [x / 10.0 for x in rng.sample(range(110, 200), 9)]
            if abs(pearson(f1, f2)) < 0.70:
                break

        rows = []
        for a, b in zip(f1, f2):
            rows.append([a, b, 100.0 - 2.0 * a, 3.0 * b + 7.0, 5.0 * a])
        headers = ["F1", "F2", "F3", "F4", "Target"]
        expected = expected_cleaned(headers, rows)

        with open(DATA, "w", newline="") as f:
            f.write(",".join(headers) + "\n")
            for row in rows:
                f.write(",".join(f"{value:.1f}" for value in row) + "\n")

        run_program()
        actual = read_output_lines()
        assert actual == expected, (
            "Go program produced incorrect output for a verification dataset. "
            f"Expected:\n{expected}\nActual:\n{actual}"
        )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
