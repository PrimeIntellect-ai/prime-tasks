#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pandas as pd
import pytest

EXPECTED_SCRIPTS = {
    "feat_a.py": "import sys, time, pandas as pd\ntime.sleep(0.5)\ndf = pd.read_csv(sys.argv[1])\nout = pd.DataFrame({'id': df['id'], 'feat_A': df['income'] * 2})\nout.to_csv('out_a.csv', index=False)\n",
    "feat_b.py": "import sys, time, pandas as pd\ntime.sleep(2.5)\ndf = pd.read_csv(sys.argv[1])\nout = pd.DataFrame({'id': df['id'], 'feat_B': df['score'] * 3})\nout.to_csv('out_b.csv', index=False)\n",
    "feat_c.py": "import sys, time, pandas as pd\ntime.sleep(1.0)\ndf = pd.read_csv(sys.argv[1])\nout = pd.DataFrame({'id': df['id'], 'feat_C': df['income'] + df['score']})\nout.to_csv('out_c.csv', index=False)\n",
}

SCRIPT_OUTPUTS = {
    "feat_a.py": ("out_a.csv", "feat_A"),
    "feat_b.py": ("out_b.csv", "feat_B"),
    "feat_c.py": ("out_c.csv", "feat_C"),
}


def expected_clean_frame():
    raw = pd.read_csv("/home/user/raw_data.csv")
    expected = raw.copy()
    expected["income"] = expected["income"].fillna(expected["income"].median())
    expected["score"] = expected["score"].fillna(0)
    expected.loc[expected["income"] > 100000, "income"] = 100000
    return expected


@pytest.fixture(scope="session")
def actual_benchmarks():
    clean_path = "/home/user/clean_data.csv"
    assert os.path.isfile(clean_path), f"Missing {clean_path}"
    clean = pd.read_csv(clean_path)
    results = {}

    for script, expected_source in EXPECTED_SCRIPTS.items():
        script_path = Path("/home/user") / script
        assert script_path.is_file(), f"Missing {script_path}"
        assert script_path.read_text() == expected_source, f"{script} was modified"

        output_name, feature_name = SCRIPT_OUTPUTS[script]
        with tempfile.TemporaryDirectory() as workdir:
            started = time.perf_counter()
            proc = subprocess.run(
                [sys.executable, str(script_path), clean_path],
                cwd=workdir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            elapsed = time.perf_counter() - started
            assert proc.returncode == 0, f"{script} failed: {proc.stderr}"

            output_path = Path(workdir) / output_name
            assert output_path.is_file(), f"{script} did not create {output_name}"
            generated = pd.read_csv(output_path)
            assert list(generated.columns) == ["id", feature_name]
            assert len(generated) == len(clean)
            pd.testing.assert_series_equal(
                generated["id"].reset_index(drop=True),
                clean["id"].reset_index(drop=True),
                check_names=False,
                check_dtype=False,
            )

            if script == "feat_a.py":
                expected_values = clean["income"] * 2
            elif script == "feat_b.py":
                expected_values = clean["score"] * 3
            else:
                expected_values = clean["income"] + clean["score"]
            pd.testing.assert_series_equal(
                generated[feature_name].reset_index(drop=True),
                expected_values.reset_index(drop=True),
                check_names=False,
                check_dtype=False,
            )
            results[script] = elapsed

    return results


def test_clean_data_csv():
    clean_data_path = "/home/user/clean_data.csv"
    assert os.path.isfile(clean_data_path), f"Missing {clean_data_path}"

    with open(clean_data_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 5, f"Expected 5 rows in clean_data.csv, got {len(rows)}"

    expected_rows = [
        {"id": "1", "income": 50000.0, "score": 80.0},
        {"id": "2", "income": 50000.0, "score": 90.0},
        {"id": "3", "income": 100000.0, "score": 0.0},
        {"id": "4", "income": 40000.0, "score": 75.0},
        {"id": "5", "income": 50000.0, "score": 85.0},
    ]

    for i, expected in enumerate(expected_rows):
        row = rows[i]
        assert float(row["id"]) == float(expected["id"]), f"Row {i+1} id mismatch"
        assert float(row["income"]) == expected["income"], f"Row {i+1} income mismatch"
        assert float(row["score"]) == expected["score"], f"Row {i+1} score mismatch"

    actual = pd.read_csv(clean_data_path)
    expected = expected_clean_frame()
    assert list(actual.columns) == list(expected.columns)
    pd.testing.assert_frame_equal(actual, expected, check_dtype=False)


def test_timing_json(actual_benchmarks):
    timing_path = "/home/user/timing.json"
    assert os.path.isfile(timing_path), f"Missing {timing_path}"

    raw_json = Path(timing_path).read_text()
    try:
        timing_data = json.loads(raw_json)
    except json.JSONDecodeError:
        pytest.fail("timing.json is not a valid JSON file")

    expected_keys = {"feat_a.py", "feat_b.py", "feat_c.py"}
    assert set(timing_data.keys()) == expected_keys, f"timing.json keys must be exactly {expected_keys}"

    for k, v in timing_data.items():
        assert isinstance(v, (int, float)), f"Value for {k} must be a number"
        assert not isinstance(v, bool) and math.isfinite(v) and v >= 0
        matches = re.findall(
            rf'"{re.escape(k)}"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{{3}})(?=\s*[,}}])',
            raw_json,
        )
        assert len(matches) == 1, f"Value for {k} must be written with exactly 3 decimal places"
        assert float(matches[0]) == float(v)

    assert timing_data["feat_b.py"] > 2.0, "feat_b.py execution time should be > 2.0s"
    assert timing_data["feat_a.py"] < 2.0, "feat_a.py execution time should be < 2.0s"
    assert timing_data["feat_c.py"] < 2.0, "feat_c.py execution time should be < 2.0s"

    # Compare the report with direct executions. The absolute allowance covers
    # small machine-load differences, while pairwise differences remove common
    # startup overhead and catch invented sleep-duration-like values.
    for script in expected_keys:
        assert abs(timing_data[script] - actual_benchmarks[script]) <= 0.35, (
            f"Reported time for {script} is inconsistent with a direct benchmark: "
            f"reported {timing_data[script]:.3f}, observed {actual_benchmarks[script]:.3f}"
        )

    pairs = [("feat_a.py", "feat_b.py"), ("feat_a.py", "feat_c.py"), ("feat_b.py", "feat_c.py")]
    for left, right in pairs:
        reported_delta = timing_data[left] - timing_data[right]
        observed_delta = actual_benchmarks[left] - actual_benchmarks[right]
        assert abs(reported_delta - observed_delta) <= 0.20, (
            f"Reported timing difference for {left} and {right} is inconsistent with direct benchmarking"
        )


def test_final_training_data_csv():
    final_data_path = "/home/user/final_training_data.csv"
    assert os.path.isfile(final_data_path), f"Missing {final_data_path}"

    with open(final_data_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)

    assert fieldnames is not None, "final_training_data.csv must have a header"

    expected_fields = {"id", "income", "score", "feat_A", "feat_C"}
    assert set(fieldnames) == expected_fields, f"final_training_data.csv columns must be exactly {expected_fields}"

    assert len(rows) == 5, f"Expected 5 rows in final_training_data.csv, got {len(rows)}"

    expected_rows = [
        {"id": "1", "income": 50000.0, "score": 80.0, "feat_A": 100000.0, "feat_C": 50080.0},
        {"id": "2", "income": 50000.0, "score": 90.0, "feat_A": 100000.0, "feat_C": 50090.0},
        {"id": "3", "income": 100000.0, "score": 0.0, "feat_A": 200000.0, "feat_C": 100000.0},
        {"id": "4", "income": 40000.0, "score": 75.0, "feat_A": 80000.0, "feat_C": 40075.0},
        {"id": "5", "income": 50000.0, "score": 85.0, "feat_A": 100000.0, "feat_C": 50085.0},
    ]

    for i, expected in enumerate(expected_rows):
        row = rows[i]
        for field, expected_val in expected.items():
            assert float(row[field]) == expected_val, f"Row {i+1} field {field} mismatch: expected {expected_val}, got {row[field]}"

    clean = expected_clean_frame()
    expected_final = clean.copy()
    expected_final["feat_A"] = expected_final["income"] * 2
    expected_final["feat_C"] = expected_final["income"] + expected_final["score"]
    actual_final = pd.read_csv(final_data_path)
    actual_final = actual_final[list(expected_final.columns)]
    pd.testing.assert_frame_equal(actual_final, expected_final, check_dtype=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
