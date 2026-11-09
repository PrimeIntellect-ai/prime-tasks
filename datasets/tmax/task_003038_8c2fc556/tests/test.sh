#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import time
import random
import tempfile
import subprocess
from collections import defaultdict

ROOTS = [15, 1024, 5000, 9999]
PACKAGE_DIR = "/app/graph_backup_validator-1.0.0"
EXECUTABLE = os.path.join(PACKAGE_DIR, "validator")
DATA_PATH = "/home/user/graph_export.jsonl"
REPORT_PATH = "/home/user/validation_report.csv"


def compute_expected_weights(data_path, roots):
    """Re-derive expected 2-hop aggregation weights from a JSONL graph."""
    edges = defaultdict(list)
    with open(data_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            e = json.loads(line)
            edges[e["src"]].append((e["dst"], e["weight"]))

    expected = {}
    for root in roots:
        total = 0
        for dst1, w1 in edges.get(root, []):
            for _, w2 in edges.get(dst1, []):
                total += w1 + w2
        expected[root] = total
    return expected


def parse_validator_csv(text):
    rows = list(csv.reader(text.splitlines()))
    assert rows, "Validator produced no output."
    assert rows[0] == ["root_id", "aggregate_weight"], \
        f"Validator CSV header mismatch: {rows[0]}"
    assert len(rows) == len(ROOTS) + 1, \
        f"Validator must output exactly one row per requested root; got {rows}."

    actual = {}
    order = []
    for row in rows[1:]:
        assert len(row) == 2, f"Invalid validator CSV row: {row}"
        try:
            root = int(row[0])
            weight = int(row[1])
        except ValueError:
            assert False, f"Invalid validator CSV row: {row}"
        assert root not in actual, f"Duplicate root in validator output: {root}"
        order.append(root)
        actual[root] = weight

    assert order == ROOTS, f"Validator output roots/order mismatch: {order}"
    return actual


def run_validator(data_path):
    return subprocess.run(
        [EXECUTABLE, "--data", data_path, "--roots", "15,1024,5000,9999", "--depth", "2"],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_validation_report_correctness():
    """Validate that the generated report matches independently computed weights."""
    assert os.path.isfile(REPORT_PATH), f"Validation report missing at {REPORT_PATH}."

    expected_weights = compute_expected_weights(DATA_PATH, ROOTS)
    actual_weights = {}
    with open(REPORT_PATH, "r") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, "Validation report is empty."

        assert header == ["root_id", "aggregate_weight"], \
            f"CSV header mismatch. Expected ['root_id', 'aggregate_weight'], got {header}."

        for row in reader:
            if not row:
                continue
            try:
                root_id = int(row[0])
                weight = int(row[1])
                actual_weights[root_id] = weight
            except ValueError:
                assert False, f"Invalid row format in CSV: {row}"

    for root in ROOTS:
        assert root in actual_weights, f"Root {root} missing from validation report."
        assert actual_weights[root] == expected_weights[root], \
            f"Incorrect aggregate weight for root {root}. Expected {expected_weights[root]}, got {actual_weights[root]}."


def test_rebuilt_validator_correctness_and_sla():
    """Rebuild from the submitted sources, validate behavior, and enforce the 0.2s SLA."""
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did you recompile it?"

    # Prevent a stale or trivial replacement executable from satisfying the test.
    os.remove(EXECUTABLE)
    build = subprocess.run(
        ["make", "-B", "validator"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, \
        f"Rebuild failed. stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    assert os.path.isfile(EXECUTABLE), "Makefile did not recreate validator."
    assert os.access(EXECUTABLE, os.X_OK), "Rebuilt validator is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validator must be a compiled ELF executable."

    start_time = time.perf_counter()
    proc = run_validator(DATA_PATH)
    elapsed = time.perf_counter() - start_time

    assert proc.returncode == 0, \
        f"Validator execution failed with return code {proc.returncode}. Stderr: {proc.stderr}"
    threshold = 0.2
    assert elapsed <= threshold, \
        f"Metric Threshold Failed: Execution took {elapsed:.4f}s. Threshold is {threshold}s."

    expected = compute_expected_weights(DATA_PATH, ROOTS)
    actual = parse_validator_csv(proc.stdout)
    assert actual == expected, f"Validator output is incorrect. Expected {expected}, got {actual}."

    with open(REPORT_PATH, "r") as f:
        report_text = f.read()
    assert proc.stdout == report_text, \
        "The validation report is not the output produced by the rebuilt validator."

    # Exercise the rebuilt artifact on a fresh graph whose answers are generated
    # at verification time, preventing hard-coded output from passing.
    rng = random.SystemRandom()
    source_ids = list(range(1, 251)) + ROOTS
    edges = []
    for src in sorted(set(source_ids)):
        for _ in range(rng.randint(2, 6)):
            edges.append({
                "src": src,
                "dst": rng.randint(1, 250),
                "weight": rng.randint(1, 20),
            })

    fd, synthetic_path = tempfile.mkstemp(prefix="validator_graph_", suffix=".jsonl")
    try:
        with os.fdopen(fd, "w") as f:
            for edge in edges:
                f.write(json.dumps(edge) + "\n")
        synthetic_expected = compute_expected_weights(synthetic_path, ROOTS)
        synthetic_proc = run_validator(synthetic_path)
        assert synthetic_proc.returncode == 0, \
            f"Validator failed on generated graph: {synthetic_proc.stderr}"
        synthetic_actual = parse_validator_csv(synthetic_proc.stdout)
        assert synthetic_actual == synthetic_expected, \
            f"Validator produced incorrect results on generated graph. Expected {synthetic_expected}, got {synthetic_actual}."
    finally:
        os.unlink(synthetic_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
