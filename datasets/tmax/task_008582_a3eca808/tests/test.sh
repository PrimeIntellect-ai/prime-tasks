#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_go_files_exist():
    """Test that the Go program and go.mod were created."""
    assert os.path.isfile('/home/user/analysis/analyze.go'), "The Go program /home/user/analysis/analyze.go is missing."
    assert os.path.isfile('/home/user/analysis/go.mod'), "The Go module file /home/user/analysis/go.mod is missing."

def test_divergence_log_matches():
    """Test that the divergence.log matches the expected output."""
    output_file = '/home/user/analysis/divergence.log'
    expected_file = '/tests/expected_divergence.log'

    assert os.path.isfile(output_file), f"{output_file} is missing."
    assert os.path.isfile(expected_file), f"Truth file {expected_file} is missing."

    with open(output_file, 'r') as f:
        output_content = f.read().strip()

    with open(expected_file, 'r') as f:
        expected_content = f.read().strip()

    assert output_content == expected_content, f"Content of {output_file} does not match expected. Got: '{output_content}', Expected: '{expected_content}'"

def test_plot_txt_matches():
    """Test that the plot.txt matches the expected output."""
    output_file = '/home/user/analysis/plot.txt'
    expected_file = '/tests/expected_plot.txt'

    assert os.path.isfile(output_file), f"{output_file} is missing."
    assert os.path.isfile(expected_file), f"Truth file {expected_file} is missing."

    with open(output_file, 'r') as f:
        output_content = f.read().strip()

    with open(expected_file, 'r') as f:
        expected_content = f.read().strip()

    assert output_content == expected_content, "Content of plot.txt does not match expected output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
