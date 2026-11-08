#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import subprocess
import pytest

def test_clean_sh_exists_and_executable():
    """Test that the script exists and is executable."""
    script_path = '/home/user/clean.sh'
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_clean_sh_output():
    """Test that the script produces the correct output based on the dataset."""
    script_path = '/home/user/clean.sh'
    data_path = '/home/user/data.csv'

    assert os.path.exists(data_path), f"Data file {data_path} is missing."

    # Run the script
    result = subprocess.run([script_path, data_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"

    agent_output = result.stdout.strip().split('\n')

    # Compute expected output
    with open(data_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    train_rows = rows[:800]

    # Calculate train age mean
    train_ages = [int(r['age']) for r in train_rows if r['age'] != '']
    train_age_mean = math.floor(sum(train_ages) / len(train_ages))

    # Calculate train income mean
    train_incomes = [float(r['income']) for r in train_rows if r['income'] != '']
    train_income_mean = sum(train_incomes) / len(train_incomes)
    income_cap = math.floor(2 * train_income_mean)

    expected_output = ["id,target,age,income"]
    for r in rows:
        age = r['age']
        if age == '':
            age = str(train_age_mean)

        income = float(r['income'])
        if income > income_cap:
            income = income_cap
        income = str(math.floor(income))

        expected_output.append(f"{r['id']},{r['target']},{age},{income}")

    assert len(agent_output) == len(expected_output), f"Output line count mismatch. Expected {len(expected_output)}, got {len(agent_output)}."

    for i, (agent_line, expected_line) in enumerate(zip(agent_output, expected_output)):
        assert agent_line.strip() == expected_line.strip(), f"Mismatch at line {i+1}. Expected '{expected_line}', got '{agent_line}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
