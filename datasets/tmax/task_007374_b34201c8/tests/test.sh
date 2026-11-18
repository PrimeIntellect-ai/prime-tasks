#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import subprocess
import csv
import math

def test_analyze_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

def test_no_forbidden_tools():
    """Test that forbidden high-level languages are not used in the script."""
    script_path = "/home/user/analyze.sh"
    with open(script_path, 'r') as f:
        content = f.read().lower()

    forbidden = ['python', 'perl', 'ruby', 'node']
    for tool in forbidden:
        assert tool not in content, f"Forbidden tool '{tool}' found in {script_path}."

def test_script_output():
    """Test that the script computes the correct leaky and strict metrics."""
    csv_path = "/home/user/embeddings.csv"
    assert os.path.isfile(csv_path), f"Missing data file: {csv_path}"

    all_v1, all_v2 = [], []
    train_v1, train_v2 = [], []
    test_data = []

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            v1 = float(row['v1'])
            v2 = float(row['v2'])
            all_v1.append(v1)
            all_v2.append(v2)
            if row['split'] == 'train':
                train_v1.append(v1)
                train_v2.append(v2)
            elif row['split'] == 'test':
                test_data.append((v1, v2))

    def mean(vals):
        return sum(vals) / len(vals)

    def std(vals, mu):
        return math.sqrt(sum((x - mu)**2 for x in vals) / len(vals))

    # Calculate Leaky parameters
    mu_all_v1 = mean(all_v1)
    std_all_v1 = std(all_v1, mu_all_v1)
    mu_all_v2 = mean(all_v2)
    std_all_v2 = std(all_v2, mu_all_v2)

    # Calculate Strict parameters
    mu_train_v1 = mean(train_v1)
    std_train_v1 = std(train_v1, mu_train_v1)
    mu_train_v2 = mean(train_v2)
    std_train_v2 = std(train_v2, mu_train_v2)

    leaky_sum = 0.0
    strict_sum = 0.0
    for v1, v2 in test_data:
        v1_leaky = (v1 - mu_all_v1) / std_all_v1
        v2_leaky = (v2 - mu_all_v2) / std_all_v2
        leaky_sum += v1_leaky * v2_leaky

        v1_strict = (v1 - mu_train_v1) / std_train_v1
        v2_strict = (v2 - mu_train_v2) / std_train_v2
        strict_sum += v1_strict * v2_strict

    leaky_metric = leaky_sum / len(test_data)
    strict_metric = strict_sum / len(test_data)

    expected_leaky = f"LEAKY: {leaky_metric:.4f}"
    expected_strict = f"STRICT: {strict_metric:.4f}"

    script_path = "/home/user/analyze.sh"
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with exit code {result.returncode} and error:\n{result.stderr}"

    output_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    assert len(output_lines) == 2, f"Expected exactly 2 lines of output, got {len(output_lines)}:\n{result.stdout}"

    assert output_lines[0] == expected_leaky, f"First line mismatch. Expected '{expected_leaky}', got '{output_lines[0]}'"
    assert output_lines[1] == expected_strict, f"Second line mismatch. Expected '{expected_strict}', got '{output_lines[1]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
