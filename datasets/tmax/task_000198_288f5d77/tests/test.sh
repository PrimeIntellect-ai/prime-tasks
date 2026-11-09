#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math

def test_model_results_exists():
    """Verify that the model_results.json file was created."""
    assert os.path.isfile("/home/user/model_results.json"), "The file /home/user/model_results.json is missing."

def test_model_results_format_and_values():
    """Verify the structure and values of the model_results.json file."""
    with open("/home/user/model_results.json", "r", encoding="utf-8") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/model_results.json is not a valid JSON file."

    assert "best_alpha" in results, "Key 'best_alpha' is missing from the JSON."
    assert "mse" in results, "Key 'mse' is missing from the JSON."

    best_alpha = results["best_alpha"]
    mse = results["mse"]

    assert isinstance(best_alpha, (int, float)), "'best_alpha' must be a number."
    assert isinstance(mse, (int, float)), "'mse' must be a number."

    # The random seed is fixed in the setup, so we expect specific values.
    # Expected best_alpha is 1.0, expected mse is around 1.3039
    expected_alpha = 1.0
    expected_mse = 1.3039

    assert math.isclose(best_alpha, expected_alpha, rel_tol=1e-3), \
        f"Expected best_alpha to be {expected_alpha}, got {best_alpha}"

    assert math.isclose(mse, expected_mse, abs_tol=1e-2), \
        f"Expected mse to be close to {expected_mse}, got {mse}"

    # Check that mse is rounded to exactly 4 decimal places
    # We can check this by verifying the string representation if we want,
    # but checking the float value is usually sufficient.
    mse_str = str(mse)
    if "." in mse_str:
        decimals = len(mse_str.split(".")[1])
        assert decimals <= 4, f"'mse' should be rounded to 4 decimal places, but found {decimals} decimal places."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
