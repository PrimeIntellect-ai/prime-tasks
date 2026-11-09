#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import subprocess
import pytest

PLOT_PATH = "/home/user/difference_plot.png"
JSON_PATH = "/home/user/analysis_results.json"


def find_analysis_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "sim_data" and not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py") and os.path.isfile(path):
                scripts.append(path)
    return sorted(scripts)


@pytest.fixture(scope="session", autouse=True)
def run_submitted_analysis_script():
    scripts = find_analysis_scripts()
    assert scripts, "No independent Python analysis script was found under /home/user"

    failures = []
    for script in scripts:
        for output in (PLOT_PATH, JSON_PATH):
            if os.path.lexists(output):
                if os.path.isdir(output) and not os.path.islink(output):
                    failures.append(f"{output} is a directory")
                    continue
                os.unlink(output)

        env = os.environ.copy()
        env["MPLBACKEND"] = "Agg"
        try:
            result = subprocess.run(
                ["python3", script],
                cwd=os.path.dirname(script) or "/home/user",
                env=env,
                capture_output=True,
                text=True,
                timeout=300,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{script}: timed out")
            continue

        if result.returncode == 0 and os.path.isfile(PLOT_PATH) and os.path.isfile(JSON_PATH):
            return

        failures.append(
            f"{script}: exit={result.returncode}, stdout={result.stdout[-500:]!r}, "
            f"stderr={result.stderr[-500:]!r}"
        )

    pytest.fail("No submitted Python script successfully produced both required outputs. " + " | ".join(failures))


def get_golden_values():
    """Dynamically recompute the expected statistics from all 50 input files."""
    script = r'''
import numpy as np
import math
import os
import json
from scipy import stats

data_dir = "/home/user/sim_data"
energies_A = []
energies_B = []

for i in range(50):
    filename = os.path.join(data_dir, f"run_{i:02d}.npy")
    if not os.path.exists(filename):
        continue
    data = np.load(filename)
    v2 = np.sum(data**2, axis=1, dtype=np.float32)
    sum_A = np.sum(v2, dtype=np.float32)
    energies_A.append(float(sum_A))
    sum_B = math.fsum(v2.flatten())
    energies_B.append(sum_B)

diffs = np.array(energies_A) - np.array(energies_B)
mean_diff = np.mean(diffs)
max_abs_diff = np.max(np.abs(diffs))
t_stat, p_val = stats.ttest_rel(energies_A, energies_B)

print(json.dumps({
    "mean_difference": float(mean_diff),
    "max_abs_difference": float(max_abs_diff),
    "t_statistic": float(t_stat),
    "p_value": float(p_val)
}))
'''
    result = subprocess.run(['python3', '-c', script], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to compute golden values: {result.stderr}")
    return json.loads(result.stdout)


def test_difference_plot_exists_and_valid():
    assert os.path.exists(PLOT_PATH), f"Plot file not found at {PLOT_PATH}"
    assert os.path.isfile(PLOT_PATH), f"{PLOT_PATH} is not a file"

    with open(PLOT_PATH, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"{PLOT_PATH} is not a valid PNG image"

    decode_script = r'''
import sys
import numpy as np
import matplotlib.image as mpimg
image = mpimg.imread(sys.argv[1])
if image.ndim not in (2, 3) or image.shape[0] < 10 or image.shape[1] < 10:
    raise SystemExit("image has invalid dimensions")
if not np.all(np.isfinite(image)):
    raise SystemExit("image contains non-finite pixels")
if float(np.max(image) - np.min(image)) <= 1e-6:
    raise SystemExit("image is blank")
'''
    decoded = subprocess.run(
        ["python3", "-c", decode_script, PLOT_PATH],
        capture_output=True,
        text=True,
    )
    assert decoded.returncode == 0, \
        f"{PLOT_PATH} is not a complete, decodable, non-blank PNG: {decoded.stderr or decoded.stdout}"


def test_analysis_results_json():
    assert os.path.exists(JSON_PATH), f"JSON results file not found at {JSON_PATH}"
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file"

    with open(JSON_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} does not contain valid JSON")

    expected_keys = {"mean_difference", "max_abs_difference", "t_statistic", "p_value"}
    actual_keys = set(results.keys())
    assert expected_keys.issubset(actual_keys), \
        f"JSON is missing expected keys. Expected {expected_keys}, got {actual_keys}"

    golden = get_golden_values()
    for key in expected_keys:
        assert isinstance(results[key], (int, float)), f"Value for {key} must be a number"
        expected_val = golden[key]
        actual_val = results[key]
        assert math.isclose(actual_val, expected_val, rel_tol=1e-4, abs_tol=1e-7), \
            f"Value for {key} is incorrect. Expected approx {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
