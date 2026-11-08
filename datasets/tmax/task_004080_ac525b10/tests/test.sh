#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_forecast_mse():
    """Test that forecast.txt exists, has 5 lines, and MSE is less than 0.05."""
    target_values = [13.10, 15.12, 17.14, 19.16, 21.18]
    forecast_file = '/home/user/forecast.txt'

    assert os.path.exists(forecast_file), f"Expected forecast file at {forecast_file} does not exist."

    with open(forecast_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 numeric values in {forecast_file}, found {len(lines)}"

    try:
        predictions = [float(line) for line in lines]
    except ValueError as e:
        pytest.fail(f"Could not parse predictions as floats: {e}")

    mse = sum((pred - target)**2 for pred, target in zip(predictions, target_values)) / 5.0

    assert mse < 0.05, f"MSE is {mse}, which is not less than the threshold of 0.05. Predictions: {predictions}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
