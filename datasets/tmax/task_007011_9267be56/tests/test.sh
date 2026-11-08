#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess

import matplotlib.image as mpimg
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

PROJECT_DIR = "/home/user/data_project"
RAW_DATA = os.path.join(PROJECT_DIR, "raw_data.csv")
PREPARE_SCRIPT = os.path.join(PROJECT_DIR, "prepare_data.sh")
PROCESSED_DATA = os.path.join(PROJECT_DIR, "processed_data.csv")
TRAIN_SCRIPT = os.path.join(PROJECT_DIR, "train_model.py")
ROC_CURVE = os.path.join(PROJECT_DIR, "roc_curve.png")
METRICS = os.path.join(PROJECT_DIR, "metrics.txt")


def expected_processed(raw_path):
    with open(raw_path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["id", "feature1", "feature2", "feature3", "target"]
    return [["id", "feature1", "feature2", "target"]] + [
        [row[0], row[1], row[2], row[4]]
        for row in rows[1:]
        if len(row) >= 5 and row[4] != ""
    ]


def read_csv_rows(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def run_prepare():
    subprocess.run(
        ["bash", PREPARE_SCRIPT], cwd=PROJECT_DIR, check=True,
        timeout=20, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def run_train():
    env = os.environ.copy()
    env.pop("DISPLAY", None)
    env.pop("MPLBACKEND", None)
    subprocess.run(
        ["python3", TRAIN_SCRIPT], cwd=PROJECT_DIR, env=env, check=True,
        timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def expected_auc(path):
    df = pd.read_csv(path)
    model = LogisticRegression()
    model.fit(df[["feature1", "feature2"]], df["target"])
    return roc_auc_score(df["target"], model.predict_proba(df[["feature1", "feature2"]])[:, 1])


def assert_outputs(expected):
    assert os.path.isfile(ROC_CURVE), f"ROC curve image {ROC_CURVE} is missing. Did the python script run successfully?"
    assert os.path.getsize(ROC_CURVE) > 0, f"ROC curve image {ROC_CURVE} is empty."
    image = mpimg.imread(ROC_CURVE)
    assert image.size > 0 and image.ndim in (2, 3), "roc_curve.png is not a decodable plot image."

    assert os.path.isfile(METRICS), f"Metrics file {METRICS} is missing."
    with open(METRICS) as f:
        metrics_content = f.read()
    assert "AUC:" in metrics_content, f"Metrics file does not contain 'AUC:'. Content: {metrics_content}"
    match = re.fullmatch(r"\s*AUC:\s*([0-9]+(?:\.[0-9]+)?)\s*", metrics_content)
    assert match, f"metrics.txt has an invalid format: {metrics_content!r}"
    actual = float(match.group(1))
    assert abs(actual - round(expected, 4)) <= 0.000051, (
        f"Reported AUC {actual} does not match the expected AUC {expected:.4f}."
    )


def remove_outputs():
    for path in (ROC_CURVE, METRICS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_complete_pipeline_behavior():
    assert os.path.isfile(PREPARE_SCRIPT), f"Bash script {PREPARE_SCRIPT} is missing."
    assert os.access(PREPARE_SCRIPT, os.X_OK) or True, "prepare_data.sh should preferably be executable."
    assert os.path.isfile(TRAIN_SCRIPT), f"Train script {TRAIN_SCRIPT} is missing."

    with open(TRAIN_SCRIPT) as f:
        content = f.read()
    assert "TkAgg" not in content, "train_model.py still contains the interactive 'TkAgg' backend."
    assert "Agg" in content or "pdf" in content.lower() or "svg" in content.lower(), \
        "train_model.py does not seem to use a non-interactive backend like 'Agg'."

    with open(RAW_DATA, "rb") as f:
        original_raw = f.read()

    try:
        # Execute the submitted ETL on the supplied data and compare every value
        # with an expectation derived directly from raw_data.csv.
        run_prepare()
        assert os.path.isfile(PROCESSED_DATA), f"Processed data file {PROCESSED_DATA} is missing."
        assert read_csv_rows(PROCESSED_DATA) == expected_processed(RAW_DATA)

        with open(PROCESSED_DATA) as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 9, f"Expected 9 lines in processed_data.csv, found {len(lines)}."
        assert lines[0] == "id,feature1,feature2,target", f"Incorrect header in processed_data.csv: {lines[0]}"
        for i, line in enumerate(lines[1:], start=2):
            parts = line.split(',')
            assert len(parts) == 4, f"Line {i} does not have exactly 4 columns: {line}"
            assert parts[3] != "", f"Line {i} has an empty target: {line}"

        # Exercise the script on fresh simple CSV data so a precomputed output
        # cannot satisfy the ETL requirement.
        rng = random.SystemRandom()
        dynamic_rows = [["id", "feature1", "feature2", "feature3", "target"]]
        for i in range(1, 15):
            target = "" if i in (3, 8, 13) else str((i + 1) % 2)
            dynamic_rows.append([
                str(1000 + i), f"{rng.uniform(-4, 4):.7f}",
                f"{rng.uniform(-3, 5):.7f}", f"unused_{rng.randrange(1000000)}", target
            ])
        with open(RAW_DATA, "w", newline="") as f:
            csv.writer(f).writerows(dynamic_rows)
        try:
            os.remove(PROCESSED_DATA)
        except FileNotFoundError:
            pass
        run_prepare()
        assert read_csv_rows(PROCESSED_DATA) == expected_processed(RAW_DATA)

        # Execute the analysis on unpredictable valid processed data and verify
        # both the calculated value and the generated image.
        model_rows = [["id", "feature1", "feature2", "target"]]
        for i in range(30):
            model_rows.append([
                str(i + 1), f"{rng.uniform(-5, 5):.8f}",
                f"{rng.uniform(-5, 5):.8f}", str(i % 2)
            ])
        with open(PROCESSED_DATA, "w", newline="") as f:
            csv.writer(f).writerows(model_rows)
        wanted_auc = expected_auc(PROCESSED_DATA)
        remove_outputs()
        run_train()
        assert_outputs(wanted_auc)
    finally:
        # Leave the requested final artifacts generated from the supplied data.
        with open(RAW_DATA, "wb") as f:
            f.write(original_raw)
        run_prepare()
        remove_outputs()
        run_train()

    assert read_csv_rows(PROCESSED_DATA) == expected_processed(RAW_DATA)
    assert_outputs(expected_auc(PROCESSED_DATA))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
