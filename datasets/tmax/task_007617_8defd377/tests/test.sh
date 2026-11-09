#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_venv_exists():
    """Check that the virtual environment was created."""
    venv_python = '/home/user/venv/bin/python'
    assert os.path.isfile(venv_python), f"Virtual environment Python executable not found at {venv_python}"

def test_output_file_exists():
    """Check that the output file was created."""
    output_file = '/home/user/largest_sync_cluster.txt'
    assert os.path.isfile(output_file), f"Output file not found at {output_file}"

def test_output_file_content():
    """Check that the output file contains the correct cluster nodes."""
    output_file = '/home/user/largest_sync_cluster.txt'
    with open(output_file, 'r') as f:
        content = f.read().strip()

    expected_nodes = ",".join(str(i) for i in range(50, 86))

    assert content == expected_nodes, (
        f"Output file content is incorrect.\n"
        f"Expected: {expected_nodes}\n"
        f"Got: {content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
