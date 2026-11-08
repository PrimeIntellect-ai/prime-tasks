#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat

def test_script_exists_and_executable():
    script_path = "/home/user/run_etl.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {script_path} is not executable by the owner."

def test_output_file_exists():
    output_path = "/home/user/output/active_project_paths.tsv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist. Did the script run successfully?"

def test_output_file_contents():
    output_path = "/home/user/output/active_project_paths.tsv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    expected_content = [
        "Alice Smith\tBob Jones\tProject Apollo",
        "Charlie Brown\tDiana Prince\tProject Hermes",
        "Eve Davis\tBob Jones\tProject Apollo"
    ]

    with open(output_path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip("\n") for line in f.readlines()]

    # Remove any trailing empty lines from actual output
    while actual_lines and actual_lines[-1] == "":
        actual_lines.pop()

    assert len(actual_lines) == len(expected_content), f"Expected {len(expected_content)} lines, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_content)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {repr(expected)}\nActual:   {repr(actual)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
