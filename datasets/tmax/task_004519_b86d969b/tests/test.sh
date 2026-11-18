#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest
import math

def test_decay_constant_accuracy():
    """Test that the estimated decay constant is within the acceptable error margin."""
    output_path = '/home/user/decay_constant.txt'

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

    try:
        with open(output_path, 'r') as f:
            content = f.read().strip()
            est_k = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {output_path} as a float. Content: '{content}'")
    except Exception as e:
        pytest.fail(f"Error reading {output_path}: {e}")

    true_k = 0.025
    error = abs(est_k - true_k)
    threshold = 0.002

    assert error <= threshold, (
        f"Estimated decay constant k={est_k} is too far from the ground truth k={true_k}. "
        f"Error: {error:.5f}, Threshold: {threshold}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
