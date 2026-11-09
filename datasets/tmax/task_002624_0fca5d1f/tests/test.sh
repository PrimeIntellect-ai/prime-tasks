#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import runpy
import subprocess
import sys

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/etl_check.py"
INPUT_PATH = "/home/user/data/input.csv"
REPORT_PATH = "/home/user/output/report.json"


def run_script():
    return subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")


def expected_from_csv(path):
    data = np.genfromtxt(path, delimiter=",", skip_header=1, dtype=np.float64)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    assert data.shape[1] == 4
    data = data[~np.isnan(data).any(axis=1)].astype(np.float64)
    X = data[:, :3]
    y = data[:, 3]
    expected_cond = np.linalg.cond(X)
    w, _, _, _ = np.linalg.lstsq(X, y, rcond=None)
    expected_mse = np.mean((y - X @ w) ** 2)
    return expected_cond, expected_mse


def assert_report_matches(path):
    report = load_report()
    assert "condition_number" in report, "Report missing 'condition_number' key."
    assert "mse" in report, "Report missing 'mse' key."
    expected_cond, expected_mse = expected_from_csv(path)
    assert np.isclose(report["condition_number"], expected_cond, rtol=1e-9, atol=1e-9), (
        f"Condition number mismatch: {report['condition_number']} != {expected_cond}"
    )
    assert np.isclose(report["mse"], expected_mse, rtol=1e-9, atol=1e-9), (
        f"MSE mismatch: {report['mse']} != {expected_mse}"
    )


def write_dataset(rows, header=("f1", "f2", "f3", "target")):
    with open(INPUT_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def test_etl_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_etl_script_numpy_config():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "invalid" in content and "raise" in content, (
        "Script does not seem to configure numpy to raise on 'invalid' errors."
    )
    assert "divide" in content and "raise" in content, (
        "Script does not seem to configure numpy to raise on 'divide' errors."
    )

    marker = "__NUMPY_ERR_STATE__"
    probe = (
        "import json, runpy, numpy as np; "
        f"runpy.run_path({SCRIPT_PATH!r}, run_name='__main__'); "
        f"print({marker!r} + json.dumps(np.geterr(), sort_keys=True))"
    )
    result = subprocess.run(
        [sys.executable, "-c", probe],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    states = [line[len(marker):] for line in result.stdout.splitlines() if line.startswith(marker)]
    assert states, "Could not inspect NumPy floating-point configuration after executing the script."
    state = json.loads(states[-1])
    assert state.get("invalid") == "raise"
    assert state.get("divide") == "raise"


def test_output_report_exists():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = run_script()
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."


def test_output_report_content():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = run_script()
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert_report_matches(INPUT_PATH)


def test_pipeline_uses_current_csv_and_computes_results():
    with open(INPUT_PATH, "rb") as f:
        original = f.read()

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    try:
        for row_count in (7, 11):
            X = rng.normal(size=(row_count, 3))
            X[:, 2] += 0.7 * X[:, 0] - 0.2 * X[:, 1]
            y = rng.normal(size=row_count) + X @ rng.normal(size=3)
            rows = np.column_stack((X, y)).tolist()
            rows[rng.integers(0, row_count)][rng.integers(0, 4)] = float("nan")
            write_dataset(rows)

            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
            result = run_script()
            assert result.returncode == 0, result.stderr
            assert os.path.isfile(REPORT_PATH), "Script did not generate report.json when executed."
            assert_report_matches(INPUT_PATH)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original)
        run_script()


def test_schema_requires_exactly_four_columns():
    with open(INPUT_PATH, "rb") as f:
        original = f.read()
    try:
        write_dataset(
            [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 3.0, 4.0, 5.0, 6.0]],
            header=("a", "b", "c", "d", "e"),
        )
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        result = run_script()
        assert result.returncode != 0, "Script accepted a CSV with five columns."
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
