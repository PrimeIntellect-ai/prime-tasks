#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import numpy as np
import pytest

SCRIPT_PATH = '/home/user/profile_hilbert.py'
JSON_PATH = '/home/user/hilbert_data.json'
PLOT_PATH = '/home/user/hilbert_plot.png'
EXPECTED_NS = [2, 4, 6, 8, 10, 12]


@pytest.fixture(scope='session', autouse=True)
def run_submission():
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/profile_hilbert.py does not exist."
    assert os.path.getsize(SCRIPT_PATH) > 0, "The script /home/user/profile_hilbert.py is empty."

    # Ensure the submitted script, rather than stale pre-created artifacts, produces
    # both requested outputs during verification.
    for path in (JSON_PATH, PLOT_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                pytest.fail(f"Expected an output file but found a directory at {path}.")
            os.unlink(path)

    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "profile_hilbert.py failed when executed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_script_exists():
    assert os.path.isfile('/home/user/profile_hilbert.py'), "The script /home/user/profile_hilbert.py does not exist."


def test_plot_exists():
    assert os.path.isfile('/home/user/hilbert_plot.png'), "The plot /home/user/hilbert_plot.png does not exist."
    assert os.path.getsize(PLOT_PATH) > 1000, "The generated plot is empty or implausibly small."
    with open(PLOT_PATH, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', "hilbert_plot.png is not a valid PNG file."

    # Decode the image to ensure it is a real, nonblank plot rather than a file
    # with only a PNG-looking header.
    import matplotlib.image as mpimg
    image = np.asarray(mpimg.imread(PLOT_PATH))
    assert image.ndim in (2, 3) and image.shape[0] > 100 and image.shape[1] > 100, \
        "The generated plot has invalid dimensions."
    assert np.isfinite(image).all(), "The generated plot contains invalid pixel values."
    assert float(np.max(image) - np.min(image)) > 0.01, "The generated plot appears blank."


def independently_compute_expected():
    expected = {}
    for n in EXPECTED_NS:
        indices = np.arange(n, dtype=float)
        h = 1.0 / (indices[:, None] + indices[None, :] + 1.0)
        x_true = np.ones(n, dtype=float)
        b = h @ x_true
        condition_number = float(np.linalg.cond(h, 2))
        x = np.linalg.solve(h, b)
        relative_error = float(np.linalg.norm(x - x_true, 2) / np.linalg.norm(x_true, 2))
        expected[str(n)] = {
            'condition_number': condition_number,
            'relative_error': relative_error,
        }
    return expected


def test_json_data():
    json_path = '/home/user/hilbert_data.json'
    assert os.path.isfile(json_path), f"The data file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "The file hilbert_data.json is not valid JSON."

    expected_Ns = ["2", "4", "6", "8", "10", "12"]
    for N in expected_Ns:
        assert N in data, f"Key '{N}' is missing from the JSON data."
        assert "condition_number" in data[N], f"Key 'condition_number' is missing for N={N}."
        assert "relative_error" in data[N], f"Key 'relative_error' is missing for N={N}."

        cond = data[N]["condition_number"]
        err = data[N]["relative_error"]

        assert isinstance(cond, (int, float)), f"Condition number for N={N} must be a float."
        assert isinstance(err, (int, float)), f"Relative error for N={N} must be a float."
        assert type(cond) is float, f"Condition number for N={N} must be a standard float."
        assert type(err) is float, f"Relative error for N={N} must be a standard float."
        assert math.isfinite(cond), f"Condition number for N={N} must be finite."
        assert math.isfinite(err), f"Relative error for N={N} must be finite."

    # Check invariants: condition numbers and errors should be strictly increasing
    conds = [data[N]["condition_number"] for N in expected_Ns]
    errs = [data[N]["relative_error"] for N in expected_Ns]

    for i in range(1, len(expected_Ns)):
        assert conds[i] > conds[i-1], f"Condition numbers should increase with N. Failed at N={expected_Ns[i]}."
        assert errs[i] > errs[i-1] or errs[i] > 1e-10, f"Relative errors should generally increase with N. Failed at N={expected_Ns[i]}."

    # Check approximate expected magnitudes for condition numbers
    assert 10 < conds[0] < 30, "Condition number for N=2 is incorrect."
    assert 1e4 < conds[1] < 3e4, "Condition number for N=4 is incorrect."
    assert 1e7 < conds[2] < 3e7, "Condition number for N=6 is incorrect."
    assert 1e15 < conds[5] < 1e18, "Condition number for N=12 is incorrect."

    # Check approximate expected magnitudes for relative errors
    assert errs[0] < 1e-12, "Relative error for N=2 is too high."
    assert errs[5] > 1e-4, "Relative error for N=12 is too low (should reflect ill-conditioning)."

    # Recompute every requested Hilbert system independently and compare the
    # submitted values to the actual NumPy results.
    expected = independently_compute_expected()
    for N in expected_Ns:
        actual_cond = data[N]['condition_number']
        actual_err = data[N]['relative_error']
        expected_cond = expected[N]['condition_number']
        expected_err = expected[N]['relative_error']

        assert math.isclose(actual_cond, expected_cond, rel_tol=1e-10, abs_tol=1e-12), (
            f"Condition number for N={N} is inaccurate: got {actual_cond}, expected {expected_cond}."
        )
        assert math.isclose(actual_err, expected_err, rel_tol=1e-6, abs_tol=1e-15), (
            f"Relative error for N={N} is inaccurate: got {actual_err}, expected {expected_err}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
