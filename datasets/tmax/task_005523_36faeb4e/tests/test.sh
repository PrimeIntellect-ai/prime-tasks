#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_ml_prep_results_json():
    """
    Validates the final state of the environment after the student performs the task.
    Checks the existence and contents of /home/user/ml_prep_results.json.
    """
    output_file = "/home/user/ml_prep_results.json"

    # Check that the output file exists
    assert os.path.exists(output_file), f"Output file {output_file} does not exist. The task was not completed successfully."
    assert os.path.isfile(output_file), f"Path {output_file} exists but is not a file."

    # Read and parse the JSON file
    with open(output_file, 'r', encoding='utf-8') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"Failed to parse JSON from {output_file}: {e}"

    # Define expected keys and types
    expected_keys = {
        "original_size": int,
        "clean_size": int,
        "best_alpha": float,
        "best_cv_score": float
    }

    # Check that all expected keys are present and have the correct type
    for key, expected_type in expected_keys.items():
        assert key in results, f"Key '{key}' is missing from the JSON output."
        assert isinstance(results[key], expected_type) or (expected_type == float and isinstance(results[key], int)), \
            f"Value for '{key}' should be of type {expected_type.__name__}, but got {type(results[key]).__name__}."

    # Check specific values
    assert results["original_size"] == 1177, f"Expected 'original_size' to be 1177, but got {results['original_size']}."
    assert results["clean_size"] == 1060, f"Expected 'clean_size' to be 1060, but got {results['clean_size']}."
    assert results["best_alpha"] == 1.0, f"Expected 'best_alpha' to be 1.0, but got {results['best_alpha']}."

    # Check best_cv_score with a tolerance
    expected_cv_score = 0.8123
    actual_cv_score = results["best_cv_score"]
    assert abs(actual_cv_score - expected_cv_score) < 0.005, \
        f"Expected 'best_cv_score' to be approximately {expected_cv_score}, but got {actual_cv_score}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
