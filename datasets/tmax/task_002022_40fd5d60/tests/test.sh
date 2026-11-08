#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import pytest

def compute_expected_metrics():
    n = 10000
    a = [i * 0.5 for i in range(1, n + 1)]
    b = [i * 1.2 + (i % 5) * 2.0 for i in range(1, n + 1)]

    dot_product = sum(x * y for x, y in zip(a, b))

    mean_a = sum(a) / n
    mean_b = sum(b) / n

    var_a = sum((x - mean_a) ** 2 for x in a)
    var_b = sum((x - mean_b) ** 2 for x in b)
    cov_ab = sum((x - mean_a) * (y - mean_b) for x, y in zip(a, b))

    correlation = cov_ab / math.sqrt(var_a * var_b)

    return f"DOT_PRODUCT={dot_product:.2f}", f"CORRELATION={correlation:.4f}"

def test_etl_metrics_log():
    """Test that the output file exists and contains the correct metrics."""
    output_file = "/home/user/etl_metrics.log"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_dot, expected_corr = compute_expected_metrics()

    assert len(lines) == 2, f"Expected exactly 2 lines in {output_file}, found {len(lines)}."

    # Check if lines match exactly
    assert lines[0] == expected_dot, f"Expected {expected_dot}, found {lines[0]}"
    assert lines[1] == expected_corr, f"Expected {expected_corr}, found {lines[1]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
