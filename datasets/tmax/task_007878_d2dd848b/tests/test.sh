#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def test_results_json_exists_and_correct():
    """
    Test that results.json exists, contains the correct keys, and matches
    the expected values derived from the canonical procedures.
    """
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"File {results_path} is missing."

    with open(results_path, "r") as f:
        try:
            student_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} does not contain valid JSON.")

    expected_keys = {"clean_row_count", "bootstrap_lower", "bootstrap_upper", "r_squared"}
    missing_keys = expected_keys - set(student_results.keys())
    assert not missing_keys, f"results.json is missing keys: {missing_keys}"

    # Recompute the expected values using the canonical logic via subprocess
    # Python Data Cleaning
    py_script = """
import pandas as pd
import numpy as np

df = pd.read_csv('/home/user/sensor_data.csv')
df['sensor_A'] = df['sensor_A'].interpolate(method='linear')
mean_B = df['sensor_B'].mean()
std_B = df['sensor_B'].std()
clean_df = df[(df['sensor_B'] >= mean_B - 3 * std_B) & (df['sensor_B'] <= mean_B + 3 * std_B)]
clean_df.to_csv('/tmp/expected_cleaned_data.csv', index=False)
print(len(clean_df))
"""
    try:
        out_py = subprocess.check_output(['python3', '-c', py_script], text=True)
        expected_count = int(out_py.strip())
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to generate expected cleaned data: {e}")

    # R Bootstrapping and Modeling
    r_script = """
df <- read.csv('/tmp/expected_cleaned_data.csv')

set.seed(42)
B <- 1000
means <- numeric(B)
for(i in 1:B) {
  means[i] <- mean(sample(df$target, replace=TRUE))
}
lower <- round(unname(quantile(means, 0.025)), 2)
upper <- round(unname(quantile(means, 0.975)), 2)

model <- lm(target ~ sensor_A + sensor_B, data=df)
r2 <- round(summary(model)$r.squared, 4)

cat(sprintf('{"bootstrap_lower": %.2f, "bootstrap_upper": %.2f, "r_squared": %.4f}', lower, upper, r2))
"""
    r_script_path = "/tmp/expected_analysis.R"
    with open(r_script_path, "w") as f:
        f.write(r_script)

    try:
        out_r = subprocess.check_output(['Rscript', r_script_path], text=True)
        expected_r = json.loads(out_r)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected R results: {e}")
    except json.JSONDecodeError:
        pytest.fail("Failed to parse expected R results JSON.")

    # Assertions
    assert student_results["clean_row_count"] == expected_count, \
        f"Expected clean_row_count to be {expected_count}, got {student_results['clean_row_count']}."

    assert student_results["bootstrap_lower"] == expected_r["bootstrap_lower"], \
        f"Expected bootstrap_lower to be {expected_r['bootstrap_lower']}, got {student_results['bootstrap_lower']}."

    assert student_results["bootstrap_upper"] == expected_r["bootstrap_upper"], \
        f"Expected bootstrap_upper to be {expected_r['bootstrap_upper']}, got {student_results['bootstrap_upper']}."

    assert student_results["r_squared"] == expected_r["r_squared"], \
        f"Expected r_squared to be {expected_r['r_squared']}, got {student_results['r_squared']}."

def test_cleaned_data_exists():
    """Test that the intermediate cleaned_data.csv exists."""
    cleaned_path = "/home/user/cleaned_data.csv"
    assert os.path.exists(cleaned_path), f"File {cleaned_path} is missing."
    assert os.path.isfile(cleaned_path), f"{cleaned_path} is not a valid file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
