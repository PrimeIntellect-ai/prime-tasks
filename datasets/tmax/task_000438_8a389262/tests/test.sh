#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import stat
import random
import subprocess
import tempfile
from types import SimpleNamespace
import pytest

PIPELINE_DIR = "/home/user/pipeline"
SCRIPT_PATH = "/home/user/run_pipeline.sh"
CSV_PATH = "/home/user/data/raw_measurements.csv"
JSON_PATH = "/home/user/data/processed.json"


def test_go_mod_exists():
    go_mod_path = "/home/user/pipeline/go.mod"
    assert os.path.isfile(go_mod_path), f"{go_mod_path} is missing. Did you initialize the go module?"
    with open(go_mod_path, "r") as f:
        content = f.read()
    assert "module data-pipeline" in content, "go.mod does not declare the module 'data-pipeline'"


def test_process_test_go_exists_and_uses_testify():
    test_file_path = "/home/user/pipeline/process_test.go"
    assert os.path.isfile(test_file_path), f"{test_file_path} is missing."
    with open(test_file_path, "r") as f:
        content = f.read()
    assert "github.com/stretchr/testify/assert" in content, "process_test.go does not use github.com/stretchr/testify/assert"
    assert "func TestNormalize" in content or "func Test" in content, "process_test.go does not seem to contain a test function"


def test_run_pipeline_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."
    with open(script_path, "r") as f:
        content = f.read()
    assert "cd /home/user/pipeline" in content, "Script does not change directory to /home/user/pipeline"
    assert "go test" in content, "Script does not run go test"
    assert "process.go" in content or "go run" in content, "Script does not run process.go"


def _run(command, cwd=None):
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        return SimpleNamespace(returncode=124, stdout=output + "\nCommand timed out")


def _check_output(ids, values):
    assert os.path.isfile(JSON_PATH), "Pipeline did not create processed.json"
    with open(JSON_PATH, "r") as f:
        data = json.load(f)
    assert isinstance(data, list), "processed.json should contain an array of objects."
    assert len(data) == len(values), "Pipeline output has the wrong number of records."
    low, high = min(values), max(values)
    expected = [0.0 if low == high else (v - low) / (high - low) for v in values]
    for index, (record, expected_id, expected_value) in enumerate(zip(data, ids, expected)):
        assert isinstance(record, dict), f"Record {index} is not an object."
        assert record.get("id") == expected_id, f"ID mismatch at index {index}."
        assert "value" in record, f"Record {index} missing 'value' field."
        assert abs(record["value"] - expected_value) <= 1e-4, (
            f"Value mismatch at index {index}: expected {expected_value}, got {record['value']}"
        )


def test_go_implementation_and_pipeline_execution():
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "process.go")), "process.go is missing."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    hidden_fd, hidden_path = tempfile.mkstemp(prefix="verifier_", suffix="_test.go", dir=PIPELINE_DIR)
    os.close(hidden_fd)
    failing_path = None
    errors = []

    hidden_test = r'''package main

import (
    "math"
    "testing"
)

func TestVerifierNormalizeCases(t *testing.T) {
    cases := []struct {
        name string
        input []float64
        expected []float64
    }{
        {"fractional", []float64{-7.5, -2.0, 3.5, 14.5}, []float64{0, 0.25, 0.5, 1}},
        {"unordered", []float64{19, 4, 10, -6}, []float64{1, 0.4, 0.64, 0}},
        {"constant", []float64{8.25, 8.25, 8.25}, []float64{0, 0, 0}},
        {"empty", []float64{}, []float64{}},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            got := Normalize(tc.input)
            if len(got) != len(tc.expected) {
                t.Fatalf("length: got %d, want %d", len(got), len(tc.expected))
            }
            for i := range got {
                if math.Abs(got[i]-tc.expected[i]) > 1e-4 {
                    t.Fatalf("index %d: got %.10f, want %.10f", i, got[i], tc.expected[i])
                }
            }
        })
    }
}
'''

    try:
        with open(hidden_path, "w") as f:
            f.write(hidden_test)

        result = _run(["go", "test", "./..."], cwd=PIPELINE_DIR)
        if result.returncode != 0:
            errors.append("Go code or tests failed to compile/run:\n" + result.stdout)

        fail_fd, failing_path = tempfile.mkstemp(prefix="verifier_fail_", suffix="_test.go", dir=PIPELINE_DIR)
        os.close(fail_fd)
        with open(failing_path, "w") as f:
            f.write('package main\nimport "testing"\nfunc TestVerifierIntentionalFailure(t *testing.T) { t.Fatal("intentional verifier failure") }\n')

        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        failed_run = _run([SCRIPT_PATH])
        if failed_run.returncode == 0:
            errors.append("run_pipeline.sh succeeded despite a failing Go test; it must gate processing on go test.")
        if os.path.exists(JSON_PATH):
            errors.append("run_pipeline.sh generated processed.json even though Go tests failed.")

        os.remove(failing_path)
        failing_path = None

        rng = random.SystemRandom()
        ids = rng.sample(range(1000, 9000), 6)
        values = [float(v) for v in rng.sample(range(-700, 1300), 6)]
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "measurement"])
            writer.writerows(zip(ids, values))

        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        successful_run = _run([SCRIPT_PATH])
        if successful_run.returncode != 0:
            errors.append("run_pipeline.sh failed on valid input:\n" + successful_run.stdout)
        else:
            try:
                _check_output(ids, values)
            except Exception as exc:
                errors.append("run_pipeline.sh produced incorrect output for verifier-derived input: " + str(exc))
    finally:
        if failing_path and os.path.exists(failing_path):
            os.remove(failing_path)
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        restored_run = _run([SCRIPT_PATH])
        if restored_run.returncode != 0:
            errors.append("run_pipeline.sh failed after restoring the original CSV:\n" + restored_run.stdout)
        if os.path.exists(hidden_path):
            os.remove(hidden_path)

    assert not errors, "\n\n".join(errors)


def test_processed_json_correctness():
    json_path = "/home/user/data/processed.json"
    csv_path = "/home/user/data/raw_measurements.csv"

    assert os.path.isfile(csv_path), "Raw CSV is missing."
    assert os.path.isfile(json_path), f"{json_path} is missing. Did the pipeline run successfully?"

    # Recompute expected values from CSV
    ids = []
    values = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ids.append(int(row["id"]))
            values.append(float(row["measurement"]))

    min_val = min(values)
    max_val = max(values)

    expected_normalized = []
    for v in values:
        if min_val == max_val:
            expected_normalized.append(0.0)
        else:
            expected_normalized.append((v - min_val) / (max_val - min_val))

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("processed.json is not a valid JSON file.")

    assert isinstance(data, list), "processed.json should contain an array of objects."
    assert len(data) == len(expected_normalized), "Mismatch in number of records in processed.json."

    for i, expected_val in enumerate(expected_normalized):
        record = data[i]
        assert "id" in record, f"Record {i} missing 'id' field."
        assert "value" in record, f"Record {i} missing 'value' field."
        assert record["id"] == ids[i], f"ID mismatch at index {i}: expected {ids[i]}, got {record['id']}"
        assert abs(record["value"] - expected_val) <= 1e-4, f"Value mismatch at index {i}: expected {expected_val}, got {record['value']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
