#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_best_config_file_exists():
    """Test that the best_config.txt file was created."""
    file_path = '/home/user/best_config.txt'
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist. Did you create it?"

def test_best_config_content():
    """Test that the best_config.txt file contains the correct best hyperparameter configuration."""
    file_path = '/home/user/best_config.txt'
    assert os.path.isfile(file_path), f"Cannot check content because {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected = "0.005,16,0.3120"
    assert content == expected, (
        f"The content of {file_path} is incorrect.\n"
        f"Expected: '{expected}'\n"
        f"Actual:   '{content}'\n"
        "Make sure you correctly filtered missing values, aggregated by mean, rounded to 4 decimal places, and found the minimum loss."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
