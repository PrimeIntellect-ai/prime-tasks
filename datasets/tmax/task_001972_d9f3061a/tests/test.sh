#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import string
import subprocess

import pytest

MODULE_DIR = "/home/user/mlops"
DATASET = "/home/user/experiments.csv"
OUTPUT = "/home/user/similar_experiments.txt"
BENCHMARK = "/home/user/benchmark_result.txt"


def run_program():
    for path in (OUTPUT, BENCHMARK):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    result = subprocess.run(
        ["go", "run", "."],
        cwd=MODULE_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_ids():
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def read_benchmark():
    assert os.path.isfile(BENCHMARK), f"Expected benchmark result file {BENCHMARK} does not exist."
    with open(BENCHMARK, "r") as f:
        content = f.read().strip()
    assert content, f"Benchmark result file {BENCHMARK} is empty."
    try:
        return float(content)
    except ValueError:
        pytest.fail(
            f"Benchmark result file {BENCHMARK} does not contain a valid numeric value, got: '{content}'"
        )


def embedding(description):
    lowered = description.lower()
    return [lowered.count(vowel) for vowel in "aeiou"]


def expected_ids_from_rows(rows):
    baseline_row = next(row for row in rows if row["ID"] == "EXP-001")
    baseline = embedding(baseline_row["Description"])
    baseline_norm = math.sqrt(sum(value * value for value in baseline))
    expected = []
    for row in rows:
        vector = embedding(row["Description"])
        norm = math.sqrt(sum(value * value for value in vector))
        similarity = 0.0 if baseline_norm == 0 or norm == 0 else sum(
            a * b for a, b in zip(baseline, vector)
        ) / (baseline_norm * norm)
        if float(row["Latency_ms"]) < 50 and similarity >= 0.85:
            expected.append(row["ID"])
    return sorted(expected)


@pytest.fixture(scope="module", autouse=True)
def execute_submission():
    run_program()


def test_similar_experiments_output():
    expected_ids = ["EXP-001", "EXP-003", "EXP-005", "EXP-007"]
    actual_ids = read_ids()
    assert actual_ids == expected_ids, f"Expected IDs {expected_ids}, but got {actual_ids} in {OUTPUT}."


def test_benchmark_result_output():
    val = read_benchmark()
    assert val >= 0, f"Benchmark result must be a positive number, got {val}."


def test_go_mod_exists_and_requires_gonum():
    go_mod_file = "/home/user/mlops/go.mod"
    assert os.path.isfile(go_mod_file), f"Expected go.mod file {go_mod_file} does not exist."
    with open(go_mod_file, "r") as f:
        content = f.read()
    assert re.search(r"(?m)^\s*module\s+mlops\s*$", content), "go.mod must declare module mlops."
    assert "gonum.org/v1/gonum" in content, (
        f"go.mod does not require 'gonum.org/v1/gonum'. Content:\n{content}"
    )


def test_analyze_go_exists_and_contains_required_implementation_elements():
    go_file = "/home/user/mlops/analyze.go"
    assert os.path.isfile(go_file), f"Expected Go source file {go_file} does not exist."

    sources = []
    for name in os.listdir(MODULE_DIR):
        if name.endswith(".go"):
            with open(os.path.join(MODULE_DIR, name), "r") as f:
                sources.append(f.read())
    source = "\n".join(sources)

    import_match = re.search(
        r'(?m)(?:\b([A-Za-z][A-Za-z0-9_]*)\s+)?"gonum\.org/v1/gonum/mat"',
        source,
    )
    assert import_match, "The Go implementation must import gonum.org/v1/gonum/mat."
    alias = import_match.group(1) or "mat"
    assert re.search(r"\b" + re.escape(alias) + r"\s*\.", source), (
        "The imported Gonum mat package must actually be used by the Go implementation."
    )

    without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", source, flags=re.MULTILINE | re.DOTALL)
    normalized = without_comments.replace("_", "")
    assert "100000" in normalized, "The implementation must configure 100,000 benchmark iterations."
    assert re.search(r"\bfor\b[^\{]*\{", without_comments), (
        "The implementation must contain the required benchmark loop."
    )


def test_program_computes_results_for_unseen_dataset():
    with open(DATASET, "rb") as f:
        original_dataset = f.read()

    rng = random.SystemRandom()
    consonants = "bcdfghjklmnpqrstvwxyz"
    tag = "".join(rng.choice(consonants) for _ in range(12))
    token = "".join(rng.choice(string.ascii_uppercase + string.digits) for _ in range(8))

    rows = [
        {"ID": "EXP-001", "Latency_ms": "49", "Accuracy": "0.90", "Description": f"aaaaa eeee {tag}"},
        {"ID": f"EXP-A-{token}", "Latency_ms": "12", "Accuracy": "0.80", "Description": "aaaaaaaaaa eeeeeeee"},
        {"ID": f"EXP-B-{token}", "Latency_ms": "50", "Accuracy": "0.99", "Description": "aaaaa eeee"},
        {"ID": f"EXP-C-{token}", "Latency_ms": "1", "Accuracy": "0.70", "Description": "uuuuuuuuuu"},
        {"ID": f"EXP-D-{token}", "Latency_ms": "30", "Accuracy": "0.85", "Description": "aaaaa eeee i"},
        {"ID": f"EXP-E-{token}", "Latency_ms": "48", "Accuracy": "0.82", "Description": "eeeeeeee"},
    ]
    expected = expected_ids_from_rows(rows)

    try:
        with open(DATASET, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["ID", "Latency_ms", "Accuracy", "Description"])
            writer.writeheader()
            writer.writerows(rows)

        run_program()
        actual = read_ids()
        assert actual == expected, (
            f"For an unseen dataset, expected IDs {expected}, but the program produced {actual}."
        )

        benchmark = read_benchmark()
        assert math.isfinite(benchmark) and benchmark > 0, (
            f"The executed 100,000-iteration benchmark must report a finite positive duration, got {benchmark}."
        )
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
