#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import math
import subprocess
import pytest

def test_pipeline_sh_exists_and_executable():
    pipeline_sh = "/home/user/pipeline.sh"
    assert os.path.isfile(pipeline_sh), f"{pipeline_sh} does not exist."
    st = os.stat(pipeline_sh)
    assert bool(st.st_mode & stat.S_IXUSR), f"{pipeline_sh} is not executable."

def test_cleaner_c_exists():
    cleaner_c = "/home/user/cleaner.c"
    assert os.path.isfile(cleaner_c), f"{cleaner_c} does not exist."

def test_pipeline_execution_and_output():
    pipeline_sh = "/home/user/pipeline.sh"
    input_file = "/home/user/signal.csv"
    output_file = "/home/user/clean_signal.csv"

    # Run the pipeline
    result = subprocess.run(["bash", pipeline_sh], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    assert os.path.isfile(output_file), f"Output file {output_file} was not generated."

    # Compute expected output dynamically based on the requirements
    with open(input_file, 'r') as f:
        lines = f.read().splitlines()

    valid_nums = []
    for line in lines:
        s = line.strip()
        if s and s != 'NaN':
            valid_nums.append(float(s))

    n = len(valid_nums)
    assert n > 0, "No valid numbers found in input."

    mean = sum(valid_nums) / n
    variance = sum((x - mean) ** 2 for x in valid_nums) / n
    std_dev = math.sqrt(variance)

    lower_bound = mean - 2.0 * std_dev
    upper_bound = mean + 2.0 * std_dev

    expected_lines = []
    for line in lines:
        s = line.strip()
        if not s or s == 'NaN':
            val = mean
        else:
            val = float(s)
            if val > upper_bound:
                val = upper_bound
            elif val < lower_bound:
                val = lower_bound
        expected_lines.append(f"{val:.4f}")

    # Verify the actual output
    with open(output_file, 'r') as f:
        actual_lines = f.read().splitlines()

    assert len(actual_lines) == len(expected_lines), f"Output file has {len(actual_lines)} lines, expected {len(expected_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected {expected}, got {actual}."

def test_cleaner_executable_exists():
    cleaner_exe = "/home/user/cleaner"
    assert os.path.isfile(cleaner_exe), f"Compiled executable {cleaner_exe} does not exist."
    st = os.stat(cleaner_exe)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled file {cleaner_exe} is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
