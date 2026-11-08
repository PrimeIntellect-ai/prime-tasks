#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_bottleneck_analysis_file_exists():
    """Test that the output file exists at the correct location."""
    file_path = '/home/user/bottleneck_analysis.txt'
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

def test_bottleneck_analysis_content():
    """Test that the output file contains the correct results."""
    file_path = '/home/user/bottleneck_analysis.txt'
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read()

    # Strip trailing whitespace for robust comparison
    parsed_lines = [line.strip() for line in content.strip().split('\n')]

    assert len(parsed_lines) == 2, f"Expected exactly 2 lines in the output file, got {len(parsed_lines)}."
    assert parsed_lines[0] == "Bottleneck: math_op", f"Expected first line to be 'Bottleneck: math_op', got '{parsed_lines[0]}'."
    assert parsed_lines[1] == "Density at mean: 1.0558", f"Expected second line to be 'Density at mean: 1.0558', got '{parsed_lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
