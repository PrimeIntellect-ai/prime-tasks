#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import subprocess
import pytest

RAW_METRICS_PATH = "/home/user/raw_metrics.csv"
CLEAN_FEATURES_PATH = "/home/user/clean_features.csv"
PREDICTIONS_PATH = "/home/user/predictions.txt"
REPORT_PATH = "/home/user/report.txt"
ETL_SCRIPT_PATH = "/home/user/run_etl.sh"
INFERENCE_SCRIPT_PATH = "/home/user/run_inference.sh"

OUTPUT_PATHS = [CLEAN_FEATURES_PATH, PREDICTIONS_PATH, REPORT_PATH]


def get_expected_clean_features():
    expected_rows = []
    if not os.path.exists(RAW_METRICS_PATH):
        return []

    with open(RAW_METRICS_PATH, "r") as f:
        reader = csv.reader(f)
        try:
            next(reader)  # Skip header
        except StopIteration:
            return []

        for row in reader:
            if len(row) != 6:
                continue
            timestamp, cpu, mem, net_in, net_out, err = row

            # Filter empty values
            if not all(row):
                continue

            # Filter error flag
            if err == "1":
                continue

            # Convert net_in and net_out
            try:
                net_in_mb = float(net_in) / 1024.0
                net_out_mb = float(net_out) / 1024.0
            except ValueError:
                continue

            expected_rows.append(f"{cpu},{mem},{net_in_mb:.2f},{net_out_mb:.2f}")

    return expected_rows


def get_expected_predictions(clean_rows):
    predictions = []
    for row in clean_rows:
        cols = row.split(",")
        cpu = float(cols[0])
        mem = float(cols[1])
        net_in = float(cols[2])
        net_out = float(cols[3])

        score = (0.6 * cpu) + (0.3 * mem) + (0.05 * net_in) + (0.05 * net_out) - 65.0
        predictions.append(1 if score > 0 else 0)
    return predictions


def read_lines(path):
    with open(path, "r") as f:
        return f.read().strip().splitlines()


def remove_outputs():
    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def assert_script(path):
    assert os.path.isfile(path), f"Script {path} does not exist or is not a regular file."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."
    with open(path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace")
    assert first_line.startswith("#!") and "bash" in first_line, f"Script {path} is not a Bash script."


def run_pipeline_and_check():
    remove_outputs()

    subprocess.run([ETL_SCRIPT_PATH], check=True, timeout=20)
    assert os.path.isfile(CLEAN_FEATURES_PATH), "ETL script did not create clean_features.csv."
    expected_clean_rows = get_expected_clean_features()
    assert read_lines(CLEAN_FEATURES_PATH) == expected_clean_rows, "ETL script produced incorrect cleaned data."

    subprocess.run([INFERENCE_SCRIPT_PATH], check=True, timeout=20)
    assert os.path.isfile(PREDICTIONS_PATH), "Inference script did not create predictions.txt."
    assert os.path.isfile(REPORT_PATH), "Pipeline scripts did not create report.txt."

    expected_preds = get_expected_predictions(expected_clean_rows)
    assert read_lines(PREDICTIONS_PATH) == [str(p) for p in expected_preds], "Inference script produced incorrect predictions."
    assert read_lines(REPORT_PATH) == [
        str(len(expected_clean_rows)),
        str(sum(expected_preds)),
        "Pipeline Complete",
    ], "Pipeline scripts produced an incorrect report."


def test_scripts_execute_pipeline_on_changed_input():
    assert_script(ETL_SCRIPT_PATH)
    assert_script(INFERENCE_SCRIPT_PATH)

    with open(RAW_METRICS_PATH, "rb") as f:
        original_raw = f.read()

    alternate_raw = """timestamp,cpu_percent,mem_percent,network_in_kb,network_out_kb,error_flag
2000000000,100,100,1024,2048,0
2000000060,0,0,0,0,0
2000000120,70,70,3072,512,0
2000000180,80,,1024,1024,0
2000000240,99,99,8192,4096,1
"""

    try:
        with open(RAW_METRICS_PATH, "w") as f:
            f.write(alternate_raw)
        run_pipeline_and_check()
    finally:
        with open(RAW_METRICS_PATH, "wb") as f:
            f.write(original_raw)
        run_pipeline_and_check()


def test_clean_features_csv():
    assert os.path.isfile(CLEAN_FEATURES_PATH), f"File {CLEAN_FEATURES_PATH} does not exist."

    expected_rows = get_expected_clean_features()

    with open(CLEAN_FEATURES_PATH, "r") as f:
        actual_content = f.read().strip().splitlines()

    assert actual_content == expected_rows, f"Content of {CLEAN_FEATURES_PATH} does not match expected cleaned data."


def test_predictions_txt():
    assert os.path.isfile(PREDICTIONS_PATH), f"File {PREDICTIONS_PATH} does not exist."

    expected_clean_rows = get_expected_clean_features()
    expected_preds = get_expected_predictions(expected_clean_rows)
    expected_preds_str = [str(p) for p in expected_preds]

    with open(PREDICTIONS_PATH, "r") as f:
        actual_preds = f.read().strip().splitlines()

    assert actual_preds == expected_preds_str, f"Content of {PREDICTIONS_PATH} does not match expected predictions."


def test_report_txt():
    assert os.path.isfile(REPORT_PATH), f"File {REPORT_PATH} does not exist."

    expected_clean_rows = get_expected_clean_features()
    expected_preds = get_expected_predictions(expected_clean_rows)

    expected_report = [
        str(len(expected_clean_rows)),
        str(sum(expected_preds)),
        "Pipeline Complete"
    ]

    with open(REPORT_PATH, "r") as f:
        actual_report = f.read().strip().splitlines()

    assert actual_report == expected_report, f"Content of {REPORT_PATH} does not match expected report."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
