#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import glob
import pytest

def get_expected_results():
    """
    Reads the CSV files and computes the expected results based on the task description.
    """
    experiments_dir = "/home/user/experiments"
    csv_files = glob.glob(os.path.join(experiments_dir, "*.csv"))

    runs_data = {}

    for file_path in csv_files:
        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                run_id = row['run_id']
                y_true = int(row['y_true'])
                y_pred = int(row['y_pred'])
                confidence = float(row['confidence'])

                if run_id not in runs_data:
                    runs_data[run_id] = {'total': 0, 'successes': 0, 'conf_sum': 0.0}

                runs_data[run_id]['total'] += 1
                if y_true == y_pred:
                    runs_data[run_id]['successes'] += 1
                runs_data[run_id]['conf_sum'] += confidence

    flagged_runs = []
    valid_successes = 0
    valid_failures = 0

    for run_id, data in runs_data.items():
        total = data['total']
        accuracy = data['successes'] / total
        mean_conf = data['conf_sum'] / total

        # Flag if accuracy < 0.60 OR abs(accuracy - mean_conf) > 0.15
        if accuracy < 0.60 or abs(accuracy - mean_conf) > 0.15:
            flagged_runs.append(run_id)
        else:
            valid_successes += data['successes']
            valid_failures += (total - data['successes'])

    flagged_runs.sort()

    # Bayesian Inference with Beta(2, 2) prior
    posterior_alpha = 2 + valid_successes
    posterior_beta = 2 + valid_failures

    return {
        "flagged_runs": flagged_runs,
        "posterior_alpha": posterior_alpha,
        "posterior_beta": posterior_beta
    }

def test_results_file_exists():
    """Test that the results.json file was created."""
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"The file {results_path} does not exist."

def test_results_content():
    """Test that the contents of results.json match the expected derived values."""
    results_path = "/home/user/results.json"
    expected = get_expected_results()

    with open(results_path, 'r', encoding='utf-8') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_path} does not contain valid JSON.")

    assert "flagged_runs" in actual, "The JSON is missing the 'flagged_runs' key."
    assert "posterior_alpha" in actual, "The JSON is missing the 'posterior_alpha' key."
    assert "posterior_beta" in actual, "The JSON is missing the 'posterior_beta' key."

    assert isinstance(actual["flagged_runs"], list), "'flagged_runs' must be a list."
    assert actual["flagged_runs"] == sorted(actual["flagged_runs"]), "'flagged_runs' list is not sorted alphabetically."

    assert actual["flagged_runs"] == expected["flagged_runs"], \
        f"Incorrect 'flagged_runs'. Expected {expected['flagged_runs']}, got {actual['flagged_runs']}."

    assert actual["posterior_alpha"] == expected["posterior_alpha"], \
        f"Incorrect 'posterior_alpha'. Expected {expected['posterior_alpha']}, got {actual['posterior_alpha']}."

    assert actual["posterior_beta"] == expected["posterior_beta"], \
        f"Incorrect 'posterior_beta'. Expected {expected['posterior_beta']}, got {actual['posterior_beta']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
