#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import sys
import subprocess

def get_expected_values():
    """
    Computes the expected values using the environment's numpy and h5py.
    This is run in a subprocess to strictly adhere to the standard library
    import constraint in the main test file.
    """
    script = """
import numpy as np
import h5py
import json

with h5py.File('/home/user/data.h5', 'r') as f:
    X = f['X'][:]
    y = f['y'][:]

U, S, Vt = np.linalg.svd(X, full_matrices=False)
rank = int(np.sum(S > 1e-8))

S_inv = np.zeros_like(S)
S_inv[:rank] = 1.0 / S[:rank]

X_pinv = Vt.T @ np.diag(S_inv) @ U.T
beta_est = X_pinv @ y

res_norm = float(np.linalg.norm(X @ beta_est - y))

b0, b1, b2 = beta_est[:3]
roots = np.roots([b0, b1, b2])
max_real_root = float(np.max(np.real(roots)))

expected_json = {
    "effective_rank": rank,
    "residual_norm": res_norm,
    "largest_root_real_part": max_real_root
}
print(json.dumps(expected_json))
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        check=True
    )
    return json.loads(result.stdout)

def test_solution_file_exists():
    """Check that the output JSON file was created."""
    assert os.path.isfile("/home/user/solution.json"), "The file /home/user/solution.json does not exist."

def test_solution_content():
    """Validate the contents of the solution JSON file against the recomputed truth."""
    solution_path = "/home/user/solution.json"
    assert os.path.isfile(solution_path), "Missing /home/user/solution.json."

    with open(solution_path, "r") as f:
        try:
            solution = json.load(f)
        except json.JSONDecodeError:
            assert False, "The file /home/user/solution.json is not valid JSON."

    expected = get_expected_values()

    # Check keys
    expected_keys = {"effective_rank", "residual_norm", "largest_root_real_part"}
    assert set(solution.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}. Found {set(solution.keys())}."

    # Check effective_rank (exact integer match)
    assert isinstance(solution["effective_rank"], int), "effective_rank must be an integer."
    assert solution["effective_rank"] == expected["effective_rank"], (
        f"Incorrect effective_rank. Expected {expected['effective_rank']}, got {solution['effective_rank']}."
    )

    # Check residual_norm (float with tolerance)
    assert isinstance(solution["residual_norm"], (int, float)), "residual_norm must be a number."
    assert math.isclose(solution["residual_norm"], expected["residual_norm"], rel_tol=1e-5), (
        f"Incorrect residual_norm. Expected ~{expected['residual_norm']}, got {solution['residual_norm']}."
    )

    # Check largest_root_real_part (float with tolerance)
    assert isinstance(solution["largest_root_real_part"], (int, float)), "largest_root_real_part must be a number."
    assert math.isclose(solution["largest_root_real_part"], expected["largest_root_real_part"], rel_tol=1e-5), (
        f"Incorrect largest_root_real_part. Expected ~{expected['largest_root_real_part']}, got {solution['largest_root_real_part']}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
