#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest
import numpy as np
import pandas as pd


def test_scripts_exist():
    deploy_script = "/home/user/planner/deploy.sh"
    forecast_script = "/home/user/planner/forecast.py"

    assert os.path.isfile(deploy_script), f"Deployment script missing: {deploy_script}"
    assert os.access(deploy_script, os.X_OK), f"Deployment script is not executable: {deploy_script}"
    assert os.path.isfile(forecast_script), f"Forecast script missing: {forecast_script}"


def test_pipeline_executes():
    forecast_file = "/home/user/planner/output/forecast.csv"
    if os.path.exists(forecast_file):
        os.remove(forecast_file)

    try:
        result = subprocess.run(
            ["/home/user/planner/deploy.sh"],
            cwd="/home/user/planner",
            env={k: v for k, v in os.environ.items() if k != "PLANNER_ENV"},
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Deployment pipeline timed out after 300 seconds.")

    assert result.returncode == 0, (
        f"Deployment pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(forecast_file), "Deployment pipeline did not create forecast.csv"


def test_forecast_output():
    forecast_file = "/home/user/planner/output/forecast.csv"
    assert os.path.isfile(forecast_file), f"Forecast output missing: {forecast_file}"

    try:
        pred_df = pd.read_csv(forecast_file)
    except Exception as e:
        pytest.fail(f"Failed to read {forecast_file}: {e}")

    assert {'day', 'predicted_load'}.issubset(pred_df.columns), f"Missing required columns in {forecast_file}. Found: {pred_df.columns}"

    pred_df = pred_df.sort_values('day')
    assert len(pred_df) == 30, f"Expected 30 predictions, got {len(pred_df)}"
    assert list(pred_df['day']) == list(range(101, 131)), "Days must be exactly 101 to 130."


def test_forecast_mse():
    forecast_file = "/home/user/planner/output/forecast.csv"
    assert os.path.isfile(forecast_file), f"Forecast output missing: {forecast_file}"

    pred_df = pd.read_csv(forecast_file).sort_values('day')

    days = np.arange(101, 131)
    base_load = 50 + 0.5 * days
    base_load = base_load * 1.05

    is_weekend = (days % 7 == 6) | (days % 7 == 0)
    true_load = base_load.copy()
    true_load[is_weekend] = base_load[is_weekend] * 0.80

    mse = np.mean((pred_df['predicted_load'].values - true_load) ** 2)

    assert mse < 2.0, f"MSE is {mse:.4f}, which is not less than the threshold of 2.0."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
