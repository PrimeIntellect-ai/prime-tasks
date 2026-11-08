#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest

RAW_PATH = "/home/user/raw_data.csv"
CLEAN_PATH = "/home/user/cleaned_data.csv"
LOG_PATH = "/home/user/experiment_log.json"
PLOT_PATH = "/home/user/plot.png"
PREP_PATH = "/home/user/prep_data.py"
VIS_PATH = "/home/user/visualize.py"


def run_script(path):
    result = subprocess.run(
        ["python3", path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
        env={k: v for k, v in os.environ.items() if k not in ("DISPLAY", "MPLBACKEND")},
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def remove_artifacts():
    for path in (CLEAN_PATH, LOG_PATH, PLOT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def validate_outputs_against(raw):
    assert os.path.isfile(CLEAN_PATH), f"Missing file: {CLEAN_PATH}"
    cleaned = pd.read_csv(CLEAN_PATH)
    assert list(cleaned.columns) == list(raw.columns), (
        f"cleaned_data.csv columns differ from source: {list(cleaned.columns)}"
    )
    assert len(cleaned) == len(raw), "cleaned_data.csv row count differs from source"

    expected = raw.copy()
    missing_count = int(expected["feature_A"].isna().sum())
    median_a = expected["feature_A"].median()
    expected["feature_A"] = expected["feature_A"].fillna(median_a)
    cap_b = raw["feature_B"].quantile(0.95)
    expected.loc[expected["feature_B"] > cap_b, "feature_B"] = cap_b

    for column in raw.columns:
        if pd.api.types.is_numeric_dtype(expected[column]):
            actual_values = pd.to_numeric(cleaned[column], errors="coerce").to_numpy(dtype=float)
            expected_values = expected[column].to_numpy(dtype=float)
            assert np.all(np.isfinite(actual_values)), f"Non-finite values found in {column}"
            assert np.allclose(actual_values, expected_values, rtol=1e-10, atol=1e-10), (
                f"Values in {column} do not match the transformation of raw_data.csv"
            )
        else:
            assert cleaned[column].tolist() == expected[column].tolist(), (
                f"Values in {column} were not preserved"
            )

    assert os.path.isfile(LOG_PATH), f"Missing file: {LOG_PATH}"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        log = json.load(f)
    assert isinstance(log, dict), "experiment_log.json must contain a dictionary"
    assert set(log) == {"imputed_count_A", "cap_value_B"}, (
        "experiment_log.json must contain exactly the required two keys"
    )
    assert type(log["imputed_count_A"]) is int, "imputed_count_A must be an integer"
    assert log["imputed_count_A"] == missing_count, "imputed_count_A is not derived from the source"
    assert isinstance(log["cap_value_B"], float), "cap_value_B must be a float"
    assert math.isclose(log["cap_value_B"], round(float(cap_b), 2), rel_tol=0, abs_tol=1e-12), (
        "cap_value_B is not the source feature_B 95th percentile rounded to 2 decimals"
    )


def validate_real_png():
    assert os.path.isfile(PLOT_PATH), f"Missing file: {PLOT_PATH}"
    with open(PLOT_PATH, "rb") as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', "plot.png is not a valid PNG image"
    image = mpimg.imread(PLOT_PATH)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1, (
        "plot.png does not contain a decodable image"
    )
    assert image.size > 0 and float(np.nanstd(image)) > 0, "plot.png contains no visible variation"


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    remove_artifacts()
    run_script(PREP_PATH)
    assert os.path.isfile(CLEAN_PATH), "prep_data.py did not generate cleaned_data.csv"
    assert os.path.isfile(LOG_PATH), "prep_data.py did not generate experiment_log.json"
    run_script(VIS_PATH)
    assert os.path.isfile(PLOT_PATH), "visualize.py did not generate plot.png"
    yield


def test_cleaned_data_matches_raw_data():
    validate_outputs_against(pd.read_csv(RAW_PATH))


def test_cleaned_data_exists_and_valid():
    path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 100, f"Expected 100 rows in cleaned_data.csv, found {len(rows)}"

    for i, row in enumerate(rows):
        assert 'feature_A' in row, "Missing column 'feature_A' in cleaned_data.csv"
        assert 'feature_B' in row, "Missing column 'feature_B' in cleaned_data.csv"

        val_A = row['feature_A'].strip()
        assert val_A != "", f"Found missing value in feature_A at row {i+1}"

        try:
            float(val_A)
        except ValueError:
            assert False, f"Non-numeric value in feature_A at row {i+1}: {val_A}"


def test_experiment_log_exists_and_valid():
    path = "/home/user/experiment_log.json"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "experiment_log.json is not a valid JSON file"

    assert "imputed_count_A" in data, "Missing key 'imputed_count_A' in experiment_log.json"
    assert data["imputed_count_A"] == 10, f"Expected imputed_count_A to be 10, got {data['imputed_count_A']}"

    assert "cap_value_B" in data, "Missing key 'cap_value_B' in experiment_log.json"
    assert isinstance(data["cap_value_B"], (int, float)), "cap_value_B must be a number"


def test_plot_png_exists_and_valid():
    path = "/home/user/plot.png"
    assert os.path.isfile(path), f"Missing file: {path}"

    # Check for valid PNG magic number
    with open(path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', "plot.png is not a valid PNG image"
    validate_real_png()


def test_feature_b_capped():
    # Verify that feature_B in cleaned_data.csv does not exceed the cap_value_B
    log_path = "/home/user/experiment_log.json"
    data_path = "/home/user/cleaned_data.csv"

    if not os.path.isfile(log_path) or not os.path.isfile(data_path):
        pytest.skip("Missing required files for cap verification")

    with open(log_path, 'r', encoding='utf-8') as f:
        try:
            log_data = json.load(f)
            cap_val = float(log_data.get("cap_value_B", float('inf')))
        except Exception:
            pytest.skip("Invalid experiment_log.json")

    with open(data_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            val_B = float(row['feature_B'])
            # Allow minor floating point differences
            assert val_B <= cap_val + 0.01, f"feature_B at row {i+1} ({val_B}) exceeds cap_value_B ({cap_val})"


def test_visualization_script_uses_agg_and_saves_without_show():
    with open(VIS_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)
    uses_agg = False
    has_savefig = False
    has_show = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            name = node.func.attr
            if name == "savefig":
                has_savefig = True
            elif name == "show":
                has_show = True
            elif name in ("use", "switch_backend"):
                if any(isinstance(arg, ast.Constant) and str(arg.value).lower() == "agg" for arg in node.args):
                    uses_agg = True
            elif name in ("setdefault", "__setitem__"):
                values = [arg.value for arg in node.args if isinstance(arg, ast.Constant)]
                if any(str(value).upper() == "MPLBACKEND" for value in values) and any(
                    str(value).lower() == "agg" for value in values
                ):
                    uses_agg = True
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
            if str(node.value.value).lower() == "agg":
                for target in node.targets:
                    if isinstance(target, ast.Subscript):
                        key = target.slice
                        if isinstance(key, ast.Constant) and str(key.value).upper() == "MPLBACKEND":
                            uses_agg = True
    assert uses_agg, "visualize.py must explicitly select the Agg backend"
    assert has_savefig, "visualize.py must save the plot with savefig"
    assert not has_show, "visualize.py must not call show()"


def test_pipeline_on_independent_input():
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()

    rng = np.random.default_rng(81723)
    alternate = pd.DataFrame({
        "id": np.arange(501, 574),
        "feature_A": rng.normal(-17.0, 4.5, 73),
        "feature_B": rng.normal(230.0, 13.0, 73),
    })
    alternate.loc[[1, 8, 19, 27, 44, 58, 70], "feature_A"] = np.nan
    alternate.loc[[0, 21, 72], "feature_B"] = [900.0, 1200.0, 1800.0]

    try:
        alternate.to_csv(RAW_PATH, index=False)
        remove_artifacts()
        run_script(PREP_PATH)
        validate_outputs_against(alternate)
        run_script(VIS_PATH)
        validate_real_png()
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        remove_artifacts()
        run_script(PREP_PATH)
        run_script(VIS_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
