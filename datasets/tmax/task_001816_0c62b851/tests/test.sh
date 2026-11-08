#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import sys
import tempfile

def test_traces_file_exists_and_format():
    """Verify that traces.txt exists, has 4 lines, formatted to 4 decimal places, and is sorted."""
    path = "/home/user/traces.txt"
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"{path} is not a valid file."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {path}, found {len(lines)}."

    values = []
    for i, line in enumerate(lines):
        assert len(line.split('.')) == 2 and len(line.split('.')[1]) == 4, \
            f"Line {i+1} ('{line}') is not formatted to exactly 4 decimal places."
        try:
            val = float(line)
            values.append(val)
        except ValueError:
            assert False, f"Line {i+1} ('{line}') is not a valid float."

    assert values == sorted(values), "The values in traces.txt are not sorted in ascending numeric order."

def test_traces_values_correct():
    """Verify the trace values against the expected computation using a subprocess."""
    path = "/home/user/traces.txt"
    assert os.path.exists(path), f"File {path} is missing."

    # We use a subprocess to compute the expected values using numpy and scipy
    # since we are restricted to stdlib in the pytest file itself.
    script = """
import numpy as np
from scipy.stats import gaussian_kde

data = np.loadtxt('/home/user/points.csv', delimiter=',')
kde = gaussian_kde(data.T)
x_grid = np.linspace(-10, 10, 100)
y_grid = np.linspace(-10, 10, 100)
X, Y = np.meshgrid(x_grid, y_grid)
grid_coords = np.vstack([X.ravel(), Y.ravel()])
Z = kde(grid_coords)

max_idx = np.argmax(Z)
x_star = X.ravel()[max_idx]
y_star = Y.ravel()[max_idx]

traces = []
quadrants = [
    (data[:, 0] >= x_star) & (data[:, 1] >= y_star),
    (data[:, 0] < x_star) & (data[:, 1] >= y_star),
    (data[:, 0] < x_star) & (data[:, 1] < y_star),
    (data[:, 0] >= x_star) & (data[:, 1] < y_star)
]

for q in quadrants:
    pts = data[q]
    if len(pts) > 1:
        cov = np.cov(pts, rowvar=False)
        try:
            L = np.linalg.cholesky(cov)
            traces.append(np.trace(L))
        except np.linalg.LinAlgError:
            traces.append(0.0)
    else:
        traces.append(0.0)

for t in sorted(traces):
    print(f"{t:.4f}")
"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as tmp:
        tmp.write(script)
        tmp_path = tmp.name

    try:
        result = subprocess.run([sys.executable, tmp_path], capture_output=True, text=True)
        assert result.returncode == 0, \
            f"Expected-value computation failed with exit code {result.returncode}: {result.stderr}"

        expected_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

        with open(path, 'r') as f:
            actual_lines = [line.strip() for line in f if line.strip()]

        assert actual_lines == expected_lines, f"Expected traces to be {expected_lines}, but got {actual_lines}."
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
