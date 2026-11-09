#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import pytest

DATA_PATH = "/home/user/data.csv"
ETL_PATH = "/home/user/etl.sh"
PREDS_PATH = "/home/user/predictions.csv"
METRICS_PATH = "/home/user/metrics.log"


def assert_predictions_csv_correct():
    assert os.path.isfile(PREDS_PATH), f"File missing: {PREDS_PATH}"

    with open(PREDS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in predictions.csv, found {len(lines)}"

    expected_values = [
        (1, 7.6, 8.6),
        (3, -1.0, -1.5),
        (5, 13.8, 13.8),
    ]

    for i, line in enumerate(lines):
        parts = line.split(',')
        assert len(parts) == 3, f"Line {i+1} does not have 3 comma-separated values: {line}"
        try:
            vals = (int(parts[0]), float(parts[1]), float(parts[2]))
        except ValueError:
            pytest.fail(f"Line {i+1} contains non-numeric values: {line}")

        assert vals[0] == expected_values[i][0], f"ID mismatch on line {i+1}: expected {expected_values[i][0]}, got {vals[0]}"
        assert abs(vals[1] - expected_values[i][1]) < 1e-6, f"Prediction mismatch on line {i+1}: expected {expected_values[i][1]}, got {vals[1]}"
        assert abs(vals[2] - expected_values[i][2]) < 1e-6, f"Target mismatch on line {i+1}: expected {expected_values[i][2]}, got {vals[2]}"


def assert_metrics_log_correct():
    assert os.path.isfile(METRICS_PATH), f"File missing: {METRICS_PATH}"

    with open(METRICS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{METRICS_PATH} is empty"
    last_line = lines[-1]
    assert last_line.startswith("MAE="), f"Last line of {METRICS_PATH} does not start with MAE=: {last_line}"

    try:
        mae_val = float(last_line.split("=")[1])
    except ValueError:
        pytest.fail(f"Could not parse MAE value from last line: {last_line}")

    assert abs(mae_val - 0.5) < 1e-6, f"MAE value mismatch: expected 0.5, got {mae_val}"


def remove_outputs():
    for path in (PREDS_PATH, METRICS_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_etl():
    result = subprocess.run(
        [ETL_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"etl.sh exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_00_original_generated_outputs():
    # Preserve the original final-state assertions, including proof that the agent
    # generated the requested files before verification began.
    assert_predictions_csv_correct()
    assert_metrics_log_correct()


def test_10_etl_script_on_unseen_data():
    assert os.path.isfile(ETL_PATH), f"File missing: {ETL_PATH}"
    mode = os.stat(ETL_PATH).st_mode
    assert stat.S_ISREG(mode), f"Not a regular file: {ETL_PATH}"
    assert os.access(ETL_PATH, os.X_OK), f"Script is not executable: {ETL_PATH}"
    with open(ETL_PATH, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "etl.sh must be an executable Bash script"

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    # Values and IDs are chosen only at verification time, so fixed fabricated
    # outputs for the setup dataset cannot satisfy this test.
    base_id = 1000 + secrets.randbelow(8000)
    valid_rows = []
    rows = []
    for i in range(8):
        row_id = base_id + i
        f1 = (secrets.randbelow(301) - 150) / 10.0
        f2 = (secrets.randbelow(301) - 150) / 10.0
        y = (secrets.randbelow(401) - 200) / 10.0
        if i in (1, 5):
            rows.append(f"{row_id},,{f2:.1f},{y:.1f}")
        elif i in (3, 7):
            rows.append(f"{row_id},{f1:.1f},,{y:.1f}")
        else:
            rows.append(f"{row_id},{f1:.1f},{f2:.1f},{y:.1f}")
            valid_rows.append((row_id, f1, f2, y))

    try:
        with open(DATA_PATH, "w") as f:
            f.write("id,f1,f2,y\n" + "\n".join(rows) + "\n")
        remove_outputs()
        run_etl()

        assert os.path.isfile(PREDS_PATH), f"File missing after executing etl.sh: {PREDS_PATH}"
        with open(PREDS_PATH) as f:
            pred_lines = [line.strip() for line in f if line.strip()]
        assert len(pred_lines) == len(valid_rows), (
            f"Expected {len(valid_rows)} valid prediction rows, found {len(pred_lines)}"
        )

        errors = []
        for line_no, (line, expected) in enumerate(zip(pred_lines, valid_rows), 1):
            parts = line.split(',')
            assert len(parts) == 3, f"Prediction line {line_no} is not id,y_pred,y: {line}"
            try:
                got_id = int(parts[0])
                got_pred = float(parts[1])
                got_y = float(parts[2])
            except ValueError:
                pytest.fail(f"Prediction line {line_no} contains non-numeric values: {line}")
            row_id, f1, f2, y = expected
            expected_pred = 2.5 * f1 - 1.2 * f2
            assert got_id == row_id, f"Expected ID {row_id}, got {got_id}"
            assert math.isfinite(got_pred) and abs(got_pred - expected_pred) < 1e-5, (
                f"Wrong prediction for ID {row_id}: expected {expected_pred}, got {got_pred}"
            )
            assert math.isfinite(got_y) and abs(got_y - y) < 1e-6, (
                f"Wrong target for ID {row_id}: expected {y}, got {got_y}"
            )
            errors.append(abs(expected_pred - y))

        assert os.path.isfile(METRICS_PATH), f"File missing after executing etl.sh: {METRICS_PATH}"
        with open(METRICS_PATH) as f:
            metric_lines = [line.strip() for line in f if line.strip()]
        assert len(metric_lines) == 1, f"Expected one appended metric, found: {metric_lines}"
        assert metric_lines[0].startswith("MAE="), f"Metric is not in MAE=<value> format: {metric_lines[0]}"
        assert metric_lines[0].count('=') == 1, f"Malformed metric line: {metric_lines[0]}"
        try:
            got_mae = float(metric_lines[0].split('=', 1)[1])
        except ValueError:
            pytest.fail(f"Could not parse MAE value: {metric_lines[0]}")
        expected_mae = sum(errors) / len(errors)
        assert math.isfinite(got_mae) and abs(got_mae - expected_mae) < 1e-5, (
            f"Wrong MAE: expected {expected_mae}, got {got_mae}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)


def test_20_execute_etl_on_original_data_and_check_final_state():
    remove_outputs()
    run_etl()
    assert_predictions_csv_correct()
    assert_metrics_log_correct()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
