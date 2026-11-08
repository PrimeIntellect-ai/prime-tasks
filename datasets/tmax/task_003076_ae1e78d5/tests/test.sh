#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from collections import Counter
from decimal import Decimal

import pytest


def pipeline_command(path):
    if path.endswith(".py"):
        return [sys.executable, path]
    if path.endswith(".sh"):
        return ["bash", path]
    if path.endswith(".R"):
        rscript = shutil.which("Rscript")
        assert rscript is not None, "An R pipeline was supplied, but Rscript is unavailable."
        return [rscript, path]
    assert os.access(path, os.X_OK), f"Pipeline {path} is not executable."
    return [path]


@pytest.fixture(scope="session", autouse=True)
def run_submitted_test_suite():
    test_script = "/home/user/test_reproducibility.sh"
    assert os.path.isfile(test_script), f"File {test_script} does not exist."

    candidates = [p for p in sorted(glob.glob("/home/user/pipeline.*")) if os.path.isfile(p)]
    assert candidates, "No pipeline script named /home/user/pipeline.<extension> was found."
    pipeline = "/home/user/pipeline.py" if "/home/user/pipeline.py" in candidates else candidates[0]

    log_path = "/home/user/test_result.log"
    if os.path.lexists(log_path):
        os.remove(log_path)

    result = subprocess.run(
        ["bash", test_script],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"The reproducibility test script failed:\n{result.stdout}"
    return pipeline


def test_test_result_log():
    log_path = "/home/user/test_result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. The testing script may not have run."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "REPRODUCIBILITY_PASS", f"Expected 'REPRODUCIBILITY_PASS' in {log_path}, but got '{content}'."


def test_aggregated_csv_batch_b():
    agg_path = "/home/user/processed/aggregated.csv"
    assert os.path.isfile(agg_path), f"File {agg_path} does not exist. The pipeline may not have produced the aggregated output."

    with open(agg_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "category,total_revenue",
        "Electronics,200.00",
        "Food,50.00"
    ]

    assert lines == expected_lines, f"Contents of {agg_path} do not match the expected output for batch_B.csv. Got: {lines}"


def test_invalid_ids_txt_batch_b():
    invalid_path = "/home/user/processed/invalid_ids.txt"
    assert os.path.isfile(invalid_path), f"File {invalid_path} does not exist. The pipeline may not have produced the invalid IDs output."

    with open(invalid_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = {
        "V1V2V3V4",
        "B1B2B3B4",
        "C1C2C3C4",
        "E1E2E3E4"
    }

    actual_ids = set(lines)

    assert len(lines) == 4, f"Expected exactly 4 lines in {invalid_path}, but got {len(lines)}."
    assert actual_ids == expected_ids, f"Contents of {invalid_path} do not match the expected invalid IDs for batch_B.csv. Got: {actual_ids}"


def test_pipeline_on_generated_hidden_dataset(run_submitted_test_suite):
    pipeline = run_submitted_test_suite

    def valid_id():
        return secrets.token_hex(4).upper()

    valid_rows = [
        [valid_id(), "Electronics", f"{secrets.randbelow(80) + 10}.{secrets.randbelow(100):02d}", str(secrets.randbelow(4) + 1)],
        [valid_id(), "Clothing", f"{secrets.randbelow(60) + 1}.{secrets.randbelow(100):02d}", str(secrets.randbelow(5) + 1)],
        [valid_id(), "Food", f"{secrets.randbelow(20)}.{secrets.randbelow(100):02d}", str(secrets.randbelow(8) + 1)],
        [valid_id(), "Electronics", f"{secrets.randbelow(30)}.{secrets.randbelow(100):02d}", str(secrets.randbelow(3) + 1)],
    ]

    bad_ids = [valid_id() for _ in range(5)]
    short_id = valid_id()[:7]
    invalid_rows = [
        [short_id, "Food", "3.25", "2"],
        [bad_ids[0], "food", "4.00", "1"],
        [bad_ids[1], "Clothing", "-0.01", "3"],
        [bad_ids[2], "Electronics", "not-a-number", "2"],
        [bad_ids[3], "Food", "7.50", "0"],
        [bad_ids[4], "Clothing", "8.00", "1.5"],
    ]
    expected_invalid = [short_id] + bad_ids

    expected = {}
    for _id, category, price, quantity in valid_rows:
        expected[category] = expected.get(category, Decimal("0")) + Decimal(price) * int(quantity)
    expected_rows = [[category, f"{expected[category]:.2f}"] for category in sorted(expected)]

    with tempfile.TemporaryDirectory(prefix="pipeline_hidden_") as root:
        input_path = os.path.join(root, "unseen.csv")
        with open(input_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "category", "price", "quantity"])
            writer.writerows(valid_rows + invalid_rows)

        aggregate_bytes = []
        first_output = None
        for index in range(2):
            output_dir = os.path.join(root, f"output_{index}")
            os.mkdir(output_dir)
            result = subprocess.run(
                pipeline_command(pipeline) + [input_path, output_dir],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
            )
            assert result.returncode == 0, f"Pipeline failed on a generated dataset:\n{result.stdout}"

            agg_path = os.path.join(output_dir, "aggregated.csv")
            invalid_path = os.path.join(output_dir, "invalid_ids.txt")
            assert os.path.isfile(agg_path), "Pipeline did not create aggregated.csv."
            assert stat.S_ISREG(os.stat(agg_path).st_mode), "aggregated.csv is not a regular file."
            assert os.path.isfile(invalid_path), "Pipeline did not create invalid_ids.txt for invalid rows."

            with open(agg_path, "rb") as f:
                aggregate_bytes.append(f.read())
            if index == 0:
                first_output = output_dir

        assert aggregate_bytes[0] == aggregate_bytes[1], "Pipeline output is not reproducible across clean runs."

        agg_path = os.path.join(first_output, "aggregated.csv")
        with open(agg_path, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["category", "total_revenue"], "aggregated.csv has the wrong header."
        assert all(len(row) == 2 for row in rows), "aggregated.csv must have exactly two columns."
        assert rows[1:] == expected_rows, f"Incorrect hidden-data aggregation: got {rows[1:]}, expected {expected_rows}."
        assert all(re.fullmatch(r"-?\d+\.\d{2}", row[1]) for row in rows[1:]), "Revenue is not formatted to exactly two decimal places."

        invalid_path = os.path.join(first_output, "invalid_ids.txt")
        with open(invalid_path) as f:
            actual_invalid = [line.rstrip("\r\n") for line in f]
        assert Counter(actual_invalid) == Counter(expected_invalid), (
            f"Incorrect invalid IDs for hidden data: got {actual_invalid}, expected {expected_invalid}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
