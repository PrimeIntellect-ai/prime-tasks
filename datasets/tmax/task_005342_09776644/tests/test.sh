#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_virtual_env_exists():
    """Verify that the Python virtual environment was created."""
    venv_python = "/home/user/bio_env/bin/python"
    assert os.path.exists(venv_python), f"Virtual environment python binary not found at {venv_python}."
    assert os.access(venv_python, os.X_OK), f"The file at {venv_python} is not executable."

def test_plot_exists():
    """Verify that the visualization plot was created and is not empty."""
    plot_path = "/home/user/motif_analysis.png"
    assert os.path.exists(plot_path), f"Plot file not found at {plot_path}."
    assert os.path.isfile(plot_path), f"Path {plot_path} is not a file."
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."

def test_json_results():
    """Verify the JSON results file structure and correctness of means/variances."""
    json_path = "/home/user/analysis_results.json"
    assert os.path.exists(json_path), f"Results file not found at {json_path}."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} does not contain valid JSON."

    assert "Component_1" in data, "Key 'Component_1' is missing from JSON."
    assert "Component_2" in data, "Key 'Component_2' is missing from JSON."

    c1 = data["Component_1"]
    c2 = data["Component_2"]

    for key in ["mean", "variance"]:
        assert key in c1, f"'Component_1' is missing the '{key}' key."
        assert key in c2, f"'Component_2' is missing the '{key}' key."

    m1 = float(c1["mean"])
    v1 = float(c1["variance"])
    m2 = float(c2["mean"])
    v2 = float(c2["variance"])

    # Check sorting
    assert m1 < m2, f"Components are not sorted by mean: {m1} is not less than {m2}."

    # Due to SVD sign ambiguity, there are two valid sets of means and corresponding variances
    # Option A: Mean1 ≈ -122.99, Mean2 ≈ 184.49, Var1 ≈ 1630.9, Var2 ≈ 1184.5
    # Option B: Mean1 ≈ -184.49, Mean2 ≈ 122.99, Var1 ≈ 1184.5, Var2 ≈ 1630.9

    def is_close(a, b, tol=1.0):
        return abs(a - b) < tol

    opt_a_means = is_close(m1, -122.99) and is_close(m2, 184.49)
    opt_b_means = is_close(m1, -184.49) and is_close(m2, 122.99)

    assert opt_a_means or opt_b_means, (
        f"Extracted means ({m1}, {m2}) do not match expected values for either SVD sign orientation."
    )

    if opt_a_means:
        assert is_close(v1, 1630.9, tol=5.0), f"Variance 1 ({v1}) does not match expected ~1630.9"
        assert is_close(v2, 1184.5, tol=5.0), f"Variance 2 ({v2}) does not match expected ~1184.5"
    else:
        assert is_close(v1, 1184.5, tol=5.0), f"Variance 1 ({v1}) does not match expected ~1184.5"
        assert is_close(v2, 1630.9, tol=5.0), f"Variance 2 ({v2}) does not match expected ~1630.9"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
