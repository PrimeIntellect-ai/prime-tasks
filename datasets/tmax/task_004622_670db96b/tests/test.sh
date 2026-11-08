#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_leaked_model_txt_exists():
    assert os.path.isfile("/home/user/leaked_model.txt"), "The file /home/user/leaked_model.txt does not exist."

def test_leaked_model_content():
    scripts_dir = "/home/user/experiments/scripts"
    logs_csv = "/home/user/experiments/logs/metrics.csv"

    # 1. Find the leaked experiment dynamically
    leaked_exp_name = None
    for i in range(1, 101):
        exp_name = f"exp_{i:03d}"
        script_path = os.path.join(scripts_dir, f"{exp_name}.py")
        if os.path.isfile(script_path):
            with open(script_path, "r") as f:
                content = f.read()
                if "scaler.fit_transform(X_test)" in content:
                    leaked_exp_name = exp_name
                    break

    assert leaked_exp_name is not None, "Could not find any script with the data leak in the initial setup."

    # 2. Find the corresponding model artifact path in the CSV
    expected_model_path = None
    assert os.path.isfile(logs_csv), f"The log file {logs_csv} is missing."
    with open(logs_csv, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("experiment_name") == leaked_exp_name:
                expected_model_path = row.get("model_artifact")
                break

    assert expected_model_path is not None, f"Could not find {leaked_exp_name} in {logs_csv}."

    # 3. Verify the content of the student's output file
    output_file = "/home/user/leaked_model.txt"
    with open(output_file, "r") as f:
        student_output = f.read().strip()

    assert student_output == expected_model_path, (
        f"Incorrect content in {output_file}. "
        f"Expected '{expected_model_path}', but got '{student_output}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
