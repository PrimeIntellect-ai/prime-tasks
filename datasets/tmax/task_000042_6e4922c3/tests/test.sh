#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math

def test_pca_output():
    input_file = "/home/user/sensor_data.csv"
    output_file = "/home/user/first_component.txt"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    # Read input data
    with open(input_file, "r") as f:
        data = [[float(x) for x in line.strip().split(",")] for line in f if line.strip()]

    N = len(data)
    assert N > 0, "Input data is empty."
    M = len(data[0])

    # Calculate means
    means = [sum(row[j] for row in data) / N for j in range(M)]

    # Mean-center data
    X_c = [[data[i][j] - means[j] for j in range(M)] for i in range(N)]

    # Compute covariance matrix C = X_c^T X_c / (N - 1)
    C = [[0.0 for _ in range(M)] for _ in range(M)]
    for i in range(M):
        for j in range(M):
            dot_product = sum(X_c[k][i] * X_c[k][j] for k in range(N))
            C[i][j] = dot_product / (N - 1)

    # Power Iteration
    v = [1.0] * M
    for _ in range(100):
        # w = C * v
        w = [sum(C[i][j] * v[j] for j in range(M)) for i in range(M)]
        # norm
        norm = math.sqrt(sum(x * x for x in w))
        # v = w / norm
        v = [x / norm for x in w]

    # Sign Determinism
    if v[0] < 0:
        v = [-x for x in v]

    # Read output data
    with open(output_file, "r") as f:
        output_lines = [line.strip() for line in f if line.strip()]

    assert len(output_lines) == M, f"Output file must contain exactly {M} lines, found {len(output_lines)}."

    output_vals = []
    for idx, line in enumerate(output_lines):
        try:
            val = float(line)
            output_vals.append(val)
        except ValueError:
            assert False, f"Line {idx+1} in output file is not a valid float: {line}"

    # Compare with tolerance
    tolerance = 1e-4
    for i in range(M):
        diff = abs(v[i] - output_vals[i])
        assert diff <= tolerance, f"Component {i} mismatch. Expected {v[i]:.6f}, got {output_vals[i]:.6f} (diff: {diff})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
