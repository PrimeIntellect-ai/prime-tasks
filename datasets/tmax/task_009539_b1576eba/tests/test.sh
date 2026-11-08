#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import pickle
import shutil
import subprocess
from collections import Counter
from decimal import Decimal, InvalidOperation

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

RAW_PATH = "/home/user/data/raw/messy_sensors.csv"
CLEAN_PATH = "/home/user/data/clean/cleaned_data.csv"
MODEL_PATH = "/home/user/model/rf_model.pkl"
METRICS_PATH = "/home/user/report/metrics.json"
COLUMNS = ["sensor_id", "temperature", "humidity", "soil_moisture", "yield_class"]


def derive_expected(raw_path):
    expected = []
    with open(raw_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == COLUMNS, f"Unexpected raw-data columns: {reader.fieldnames}"
        for row in reader:
            sensor_id = row["sensor_id"]
            if not sensor_id.startswith("GH-"):
                continue
            try:
                temp = float(row["temperature"])
                hum = float(row["humidity"])
                soil = float(row["soil_moisture"])
                yc_decimal = Decimal(row["yield_class"])
            except (ValueError, InvalidOperation):
                continue
            if not all(math.isfinite(v) for v in (temp, hum, soil)):
                continue
            if not yc_decimal.is_finite() or yc_decimal != yc_decimal.to_integral_value():
                continue
            yc = int(yc_decimal)
            if not (10.0 <= temp <= 40.0):
                continue
            if not (20.0 <= hum <= 90.0):
                continue
            if not (0.0 <= soil <= 100.0):
                continue
            if yc not in {0, 1, 2}:
                continue
            expected.append((sensor_id, temp, hum, soil, yc))
    return expected


@pytest.fixture(scope="session")
def pipeline_run():
    pipeline_script = "/home/user/pipeline.py"
    bash_script = "/home/user/run_pipeline.sh"

    assert os.path.exists(pipeline_script), f"Python script {pipeline_script} does not exist."
    assert os.path.isfile(pipeline_script), f"{pipeline_script} is not a file."
    assert os.path.exists(bash_script), f"Bash script {bash_script} does not exist."
    assert os.path.isfile(bash_script), f"{bash_script} is not a file."
    assert os.access(bash_script, os.X_OK), f"Bash script {bash_script} is not executable."

    with open(RAW_PATH, "rb") as f:
        raw_before = f.read()
    expected = derive_expected(RAW_PATH)

    for path in ("/home/user/data/clean", "/home/user/model", "/home/user/report"):
        shutil.rmtree(path, ignore_errors=True)

    try:
        result = subprocess.run(
            ["./run_pipeline.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("./run_pipeline.sh did not finish within 180 seconds.")

    assert result.returncode == 0, (
        "./run_pipeline.sh failed with exit code " + str(result.returncode)
        + "\nstdout:\n" + result.stdout + "\nstderr:\n" + result.stderr
    )
    with open(RAW_PATH, "rb") as f:
        assert f.read() == raw_before, "The pipeline modified the raw input CSV."
    return expected


def test_scripts_exist_and_executable(pipeline_run):
    pipeline_script = "/home/user/pipeline.py"
    bash_script = "/home/user/run_pipeline.sh"
    assert os.path.exists(pipeline_script), f"Python script {pipeline_script} does not exist."
    assert os.path.isfile(pipeline_script), f"{pipeline_script} is not a file."
    assert os.path.exists(bash_script), f"Bash script {bash_script} does not exist."
    assert os.path.isfile(bash_script), f"{bash_script} is not a file."
    assert os.access(bash_script, os.X_OK), f"Bash script {bash_script} is not executable."


def read_and_validate_cleaned():
    assert os.path.exists(CLEAN_PATH), f"Cleaned data file {CLEAN_PATH} does not exist."
    assert os.path.isfile(CLEAN_PATH), f"{CLEAN_PATH} is not a file."

    with open(CLEAN_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == COLUMNS, f"Expected columns {COLUMNS}, found {reader.fieldnames}."
        rows = list(reader)

    parsed = []
    for i, row in enumerate(rows):
        sensor_id = row.get("sensor_id", "")
        assert sensor_id.startswith("GH-"), f"Row {i}: sensor_id '{sensor_id}' does not start with 'GH-'."

        try:
            temp = float(row.get("temperature", ""))
            assert math.isfinite(temp) and 10.0 <= temp <= 40.0, f"Row {i}: temperature {temp} is out of bounds [10.0, 40.0]."
        except ValueError:
            pytest.fail(f"Row {i}: temperature '{row.get('temperature')}' is not a valid float.")

        try:
            hum = float(row.get("humidity", ""))
            assert math.isfinite(hum) and 20.0 <= hum <= 90.0, f"Row {i}: humidity {hum} is out of bounds [20.0, 90.0]."
        except ValueError:
            pytest.fail(f"Row {i}: humidity '{row.get('humidity')}' is not a valid float.")

        try:
            soil = float(row.get("soil_moisture", ""))
            assert math.isfinite(soil) and 0.0 <= soil <= 100.0, f"Row {i}: soil_moisture {soil} is out of bounds [0.0, 100.0]."
        except ValueError:
            pytest.fail(f"Row {i}: soil_moisture '{row.get('soil_moisture')}' is not a valid float.")

        try:
            yc = int(row.get("yield_class", ""))
            assert yc in {0, 1, 2}, f"Row {i}: yield_class {yc} is not in {{0, 1, 2}}."
        except ValueError:
            pytest.fail(f"Row {i}: yield_class '{row.get('yield_class')}' is not a valid integer.")

        parsed.append((sensor_id, temp, hum, soil, yc))
    return parsed


def test_cleaned_data_exists_and_correct(pipeline_run):
    actual = read_and_validate_cleaned()
    assert len(actual) == 20, f"Expected 20 data rows in cleaned dataset, found {len(actual)}."
    assert Counter(actual) == Counter(pipeline_run), "Cleaned rows do not exactly match the valid rows derived from the raw CSV."


def load_model(path):
    try:
        return joblib.load(path)
    except Exception as joblib_error:
        try:
            with open(path, "rb") as f:
                return pickle.load(f)
        except Exception as pickle_error:
            pytest.fail(f"Could not load model with joblib or pickle: {joblib_error}; {pickle_error}")


def test_model_and_metrics_are_correct(pipeline_run):
    assert os.path.exists(MODEL_PATH), f"Model file {MODEL_PATH} does not exist."
    assert os.path.isfile(MODEL_PATH), f"{MODEL_PATH} is not a file."
    assert os.path.getsize(MODEL_PATH) > 0, f"Model file {MODEL_PATH} is empty."

    model = load_model(MODEL_PATH)
    assert type(model) is RandomForestClassifier, f"Expected RandomForestClassifier, found {type(model).__name__}."
    assert model.n_estimators == 50, f"Expected n_estimators=50, found {model.n_estimators}."
    assert model.random_state == 42, f"Expected random_state=42, found {model.random_state}."
    assert hasattr(model, "estimators_") and len(model.estimators_) == 50, "The saved classifier is not fitted with 50 trees."

    actual = read_and_validate_cleaned()
    frame = pd.DataFrame(actual, columns=COLUMNS)
    X = frame[["temperature", "humidity", "soil_moisture"]]
    y = frame["yield_class"]
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    reference = RandomForestClassifier(n_estimators=50, random_state=42)
    reference.fit(X_train, y_train)

    assert np.array_equal(model.classes_, reference.classes_), "The model has incorrect learned classes."
    np.testing.assert_allclose(
        model.predict_proba(X),
        reference.predict_proba(X),
        rtol=0.0,
        atol=0.0,
        err_msg="The saved model does not match a RandomForest trained on the required cleaned-data split.",
    )

    model_accuracy = float(model.score(X_test, y_test))
    expected_accuracy = float(reference.score(X_test, y_test))
    assert model_accuracy == pytest.approx(expected_accuracy, abs=1e-12), "Saved model accuracy does not match the required training procedure."

    assert os.path.exists(METRICS_PATH), f"Metrics file {METRICS_PATH} does not exist."
    assert os.path.isfile(METRICS_PATH), f"{METRICS_PATH} is not a file."
    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Metrics file {METRICS_PATH} does not contain valid JSON.")

    assert isinstance(metrics, dict), "metrics.json must contain a JSON object."
    assert set(metrics) == {"accuracy"}, "metrics.json must contain exactly the key 'accuracy'."
    assert isinstance(metrics["accuracy"], float), f"Value for 'accuracy' must be a float, found {type(metrics['accuracy']).__name__}."
    assert 0.0 <= metrics["accuracy"] <= 1.0, f"Accuracy {metrics['accuracy']} is out of bounds [0.0, 1.0]."
    assert metrics["accuracy"] == pytest.approx(model_accuracy, abs=1e-12), "Reported accuracy does not equal the saved model's accuracy on the required test split."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
