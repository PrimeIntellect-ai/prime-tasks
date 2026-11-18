#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import math
import os
import subprocess

import pytest

VENV_PYTHON = "/home/user/venv/bin/python"
SCRIPT_PATH = "/home/user/generate_report.py"
CSV_PATH = "/home/user/experiments.csv"
REPORT_PATH = "/home/user/report.json"
PLOT_PATH = "/home/user/artifacts/correlation_plot.png"
EXPECTED_KEYS = {
    "correlation_coefficient",
    "correlation_p_value",
    "t_statistic",
    "t_test_p_value",
}


def run_report():
    for path in (REPORT_PATH, PLOT_PATH):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["DISPLAY"] = ""
    result = subprocess.run(
        [VENV_PYTHON, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"generate_report.py failed. stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Script did not generate /home/user/report.json"
    assert os.path.isfile(PLOT_PATH), "Script did not generate the required plot"


def load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON")


def compute_expected():
    compute_script = r'''
import pandas as pd
import scipy.stats as stats
import json

df = pd.read_csv('/home/user/experiments.csv')
corr, p_corr = stats.pearsonr(df['learning_rate'], df['val_loss'])
t_stat, p_t = stats.ttest_ind(
    df[df['architecture'] == 'Arch_A']['val_loss'],
    df[df['architecture'] == 'Arch_B']['val_loss'],
    equal_var=True
)
print(json.dumps({
    "correlation_coefficient": round(corr, 4),
    "correlation_p_value": round(p_corr, 4),
    "t_statistic": round(t_stat, 4),
    "t_test_p_value": round(p_t, 4)
}))
'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", compute_script], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Failed to compute expected values: {result.stderr}"
    return json.loads(result.stdout)


def assert_report_matches_expected(results, expected):
    assert set(results.keys()) == EXPECTED_KEYS, (
        f"JSON keys do not match expected. Found: {list(results.keys())}"
    )
    for key in EXPECTED_KEYS:
        actual_val = results[key]
        expected_val = expected[key]
        assert isinstance(actual_val, (int, float)) and not isinstance(actual_val, bool), \
            f"Value for {key} must be a number"
        assert math.isfinite(actual_val), f"Value for {key} must be finite"
        assert math.isclose(actual_val, expected_val, rel_tol=1e-4, abs_tol=1e-4), \
            f"Expected {key} to be {expected_val}, but got {actual_val}"


def verify_scatter_call():
    capture_path = "/tmp/scatter_calls.json"
    if os.path.exists(capture_path):
        os.remove(capture_path)
    wrapper = r'''
import json
import runpy
import matplotlib
matplotlib.use("Agg")
from matplotlib.axes import Axes

calls = []
_original_scatter = Axes.scatter

def recording_scatter(self, x, y, *args, **kwargs):
    calls.append({
        "x": [float(v) for v in list(x)],
        "y": [float(v) for v in list(y)],
    })
    return _original_scatter(self, x, y, *args, **kwargs)

Axes.scatter = recording_scatter
try:
    runpy.run_path("/home/user/generate_report.py", run_name="__main__")
finally:
    with open("/tmp/scatter_calls.json", "w") as f:
        json.dump(calls, f)
'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", wrapper],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Instrumented script run failed: {result.stderr}"
    assert os.path.isfile(capture_path), "Could not observe plotting behavior"
    with open(capture_path) as f:
        calls = json.load(f)
    with open(CSV_PATH, newline="") as f:
        rows = list(csv.DictReader(f))
    expected_x = [float(row["learning_rate"]) for row in rows]
    expected_y = [float(row["val_loss"]) for row in rows]

    def same(values, expected):
        return len(values) == len(expected) and all(
            math.isclose(a, b, rel_tol=1e-10, abs_tol=1e-12)
            for a, b in zip(values, expected)
        )

    assert any(same(call["x"], expected_x) and same(call["y"], expected_y) for call in calls), \
        "The script did not create a scatter plot of all learning_rate values versus val_loss"


@pytest.fixture(scope="session", autouse=True)
def exercise_script_on_data():
    assert os.path.isfile(VENV_PYTHON), f"Virtual environment python not found at {VENV_PYTHON}"
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    dep_check = subprocess.run(
        [VENV_PYTHON, "-c", "import pandas, scipy, matplotlib"],
        capture_output=True,
        text=True,
    )
    assert dep_check.returncode == 0, f"Dependencies not installed in venv: {dep_check.stderr}"

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        run_report()
        original_expected = compute_expected()
        assert_report_matches_expected(load_report(), original_expected)
        with open(PLOT_PATH, "rb") as f:
            original_plot_hash = hashlib.sha256(f.read()).hexdigest()

        verify_scatter_call()

        with open(CSV_PATH, newline="") as f:
            rows = list(csv.DictReader(f))
            fieldnames = list(rows[0].keys())
        for i, row in enumerate(rows):
            lr = 0.003 + (i + 1) * 0.0017
            arch_offset = 0.065 if row["architecture"] == "Arch_B" else -0.025
            loss = 0.82 - 2.7 * lr + arch_offset + ((i % 5) - 2) * 0.006
            row["learning_rate"] = repr(lr)
            row["val_loss"] = repr(loss)
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

        run_report()
        variant_expected = compute_expected()
        assert_report_matches_expected(load_report(), variant_expected)
        with open(PLOT_PATH, "rb") as f:
            variant_plot_hash = hashlib.sha256(f.read()).hexdigest()
        assert variant_plot_hash != original_plot_hash, \
            "Plot output did not change when the plotted dataset changed"
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        run_report()


def test_venv_and_dependencies():
    assert os.path.isfile(VENV_PYTHON), f"Virtual environment python not found at {VENV_PYTHON}"
    result = subprocess.run(
        [VENV_PYTHON, "-c", "import pandas, scipy, matplotlib"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Dependencies not installed in venv. Error: {result.stderr}"


def test_plot_exists():
    assert os.path.isfile(PLOT_PATH), f"Plot file not found at {PLOT_PATH}"
    assert os.path.getsize(PLOT_PATH) > 0, f"Plot file {PLOT_PATH} is empty"
    with open(PLOT_PATH, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "Plot is not a PNG file"

    image_check = r'''
import json
import numpy as np
import matplotlib.image as mpimg
img = mpimg.imread('/home/user/artifacts/correlation_plot.png')
print(json.dumps({
    "shape": list(img.shape),
    "finite": bool(np.isfinite(img).all()),
    "std": float(np.std(img)),
    "range": float(np.max(img) - np.min(img)),
}))
'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", image_check], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Plot is not a readable PNG image: {result.stderr}"
    info = json.loads(result.stdout)
    assert len(info["shape"]) in (2, 3) and info["shape"][0] >= 100 and info["shape"][1] >= 100, \
        f"Plot has invalid dimensions: {info['shape']}"
    assert info["finite"], "Plot contains invalid pixel values"
    assert info["std"] > 0.01 and info["range"] > 0.1, "Plot image has no meaningful visual content"


def test_report_json_correctness():
    assert os.path.isfile(REPORT_PATH), f"Report JSON not found at {REPORT_PATH}"
    results = load_report()
    expected_results = compute_expected()
    assert_report_matches_expected(results, expected_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
