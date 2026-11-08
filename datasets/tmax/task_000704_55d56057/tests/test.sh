#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT_PATH = "/home/user/run_analysis.sh"
DATASET_PATH = "/home/user/dataset.csv"
OUTPUT_PATHS = [
    "/home/user/cleaned_dataset.csv",
    "/home/user/ci.txt",
    "/home/user/retrieved_id.txt",
]


def run_script_fresh():
    for path in OUTPUT_PATHS:
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=120,
    )


def test_00_execute_requested_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    run_script_fresh()


def test_script_exists_and_executable():
    script_path = "/home/user/run_analysis.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_cleaned_dataset():
    cleaned_path = "/home/user/cleaned_dataset.csv"
    assert os.path.isfile(cleaned_path), f"Cleaned dataset {cleaned_path} does not exist."

    with open(cleaned_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 5, f"Expected 5 rows (including header) in {cleaned_path}, found {len(rows)}."
    assert rows[0] == ["record_id", "measurement", "notes"], "Header is incorrect or missing."

    record_ids = [row[0] for row in rows[1:]]
    assert "2" not in record_ids, "Row with NaN measurement was not removed."
    assert "3" not in record_ids, "Row with measurement > 100 was not removed."
    assert "5" not in record_ids, "Row with measurement < 0 was not removed."

    expected_ids = {"1", "4", "6", "7"}
    assert set(record_ids) == expected_ids, f"Expected record IDs {expected_ids}, found {set(record_ids)}."


def test_ci_output():
    ci_path = "/home/user/ci.txt"
    assert os.path.isfile(ci_path), f"Confidence interval file {ci_path} does not exist."

    with open(ci_path, "r") as f:
        content = f.read().strip()

    assert "44.55,46.45" in content, f"Expected CI '44.55,46.45' in {ci_path}, but got '{content}'."
    assert re.fullmatch(r"-?\d+(?:\.\d{2}),-?\d+(?:\.\d{2})", content), \
        f"CI output must strictly contain lower_bound,upper_bound rounded to 2 decimals, got '{content}'."


def test_retrieved_id():
    id_path = "/home/user/retrieved_id.txt"
    assert os.path.isfile(id_path), f"Retrieved ID file {id_path} does not exist."

    with open(id_path, "r") as f:
        content = f.read().strip()

    assert content == "4", f"Expected retrieved ID '4', but got '{content}'."


def test_pipeline_recomputes_from_dataset():
    with open("/home/user/ci.txt", "r") as f:
        baseline_ci = f.read().strip()
    match = re.fullmatch(r"(-?\d+(?:\.\d{2})),(-?\d+(?:\.\d{2}))", baseline_ci)
    assert match, f"Could not parse baseline CI '{baseline_ci}'."
    baseline_lower, baseline_upper = map(float, match.groups())

    with open(DATASET_PATH, "rb") as f:
        original_dataset = f.read()

    changed_dataset = """record_id,measurement,notes
101,55.2,normal operation detected
102,NaN,system failure missing data
103,1050.5,extreme spike in temperature
104,54.8,stable baseline reading recorded
105,-5.0,sensor calibration error
106,56.1,routine check baseline
107,55.9,stable operation
"""

    try:
        with open(DATASET_PATH, "w", newline="") as f:
            f.write(changed_dataset)
        run_script_fresh()

        with open(DATASET_PATH, "r", newline="") as f:
            source_rows = list(csv.DictReader(f))

        expected_rows = []
        for row in source_rows:
            raw = row["measurement"].strip()
            if raw == "" or raw.lower() in {"nan", "null"}:
                continue
            value = float(raw)
            if math.isnan(value) or value < 0.0 or value > 100.0:
                continue
            expected_rows.append({
                "record_id": row["record_id"],
                "measurement": value,
                "notes": row["notes"],
            })

        with open("/home/user/cleaned_dataset.csv", "r", newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["record_id", "measurement", "notes"]
            actual_rows = list(reader)

        assert len(actual_rows) == len(expected_rows)
        actual_by_id = {row["record_id"]: row for row in actual_rows}
        assert set(actual_by_id) == {row["record_id"] for row in expected_rows}
        for expected in expected_rows:
            actual = actual_by_id[expected["record_id"]]
            assert float(actual["measurement"]) == pytest.approx(expected["measurement"])
            assert actual["notes"] == expected["notes"]

        with open("/home/user/ci.txt", "r") as f:
            changed_ci = f.read().strip()
        changed_match = re.fullmatch(r"(-?\d+(?:\.\d{2})),(-?\d+(?:\.\d{2}))", changed_ci)
        assert changed_match, f"Invalid recomputed CI format: '{changed_ci}'."
        changed_lower, changed_upper = map(float, changed_match.groups())
        assert changed_lower == pytest.approx(baseline_lower + 10.0, abs=0.005)
        assert changed_upper == pytest.approx(baseline_upper + 10.0, abs=0.005)

        notes = [row["notes"] for row in expected_rows]
        vectorizer = TfidfVectorizer()
        matrix = vectorizer.fit_transform(notes + ["stable baseline reading"])
        similarities = cosine_similarity(matrix[:-1], matrix[-1]).ravel()
        expected_id = expected_rows[int(similarities.argmax())]["record_id"]

        with open("/home/user/retrieved_id.txt", "r") as f:
            actual_id = f.read().strip()
        assert actual_id == expected_id, f"Expected dynamically derived ID {expected_id}, got {actual_id}."
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original_dataset)
        run_script_fresh()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
