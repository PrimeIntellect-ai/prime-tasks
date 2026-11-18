#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess

import pytest

VENV_PYTHON = "/home/user/perf_env/bin/python"
SCRIPT_PATH = "/home/user/analyze_perf.py"
REPORT_PATH = "/home/user/perf_report.json"
V1_PATH = "/home/user/latency_v1.csv"
V2_PATH = "/home/user/latency_v2.csv"


def run_analysis():
    result = subprocess.run(
        [VENV_PYTHON, SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Analysis script failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_report():
    assert os.path.exists(REPORT_PATH), f"JSON report not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a valid file"
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} does not contain valid JSON")

    assert set(data.keys()) == {"wasserstein_distance", "ks_p_value"}, (
        "Report must contain exactly wasserstein_distance and ks_p_value"
    )
    assert "wasserstein_distance" in data, "Key 'wasserstein_distance' missing from report"
    assert "ks_p_value" in data, "Key 'ks_p_value' missing from report"
    assert isinstance(data["wasserstein_distance"], (int, float)), (
        "wasserstein_distance must be a number"
    )
    assert isinstance(data["ks_p_value"], (int, float)), "ks_p_value must be a number"
    assert math.isfinite(data["wasserstein_distance"])
    assert math.isfinite(data["ks_p_value"])
    return data


def scipy_expected():
    code = r'''import json
import numpy as np
from scipy.stats import wasserstein_distance, ks_2samp
v1 = np.loadtxt("/home/user/latency_v1.csv")
v2 = np.loadtxt("/home/user/latency_v2.csv")
print(json.dumps({
    "wasserstein_distance": round(float(wasserstein_distance(v1, v2)), 4),
    "ks_p_value": round(float(ks_2samp(v1, v2).pvalue), 4),
}))'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", code],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        "NumPy/SciPy could not compute reference statistics in the virtual environment:\n"
        + result.stderr
    )
    return json.loads(result.stdout)


def test_virtual_environment_exists():
    assert os.path.exists(VENV_PYTHON), f"Virtual environment python not found at {VENV_PYTHON}"
    assert os.path.isfile(VENV_PYTHON), f"{VENV_PYTHON} is not a valid file"
    check = subprocess.run(
        [VENV_PYTHON, "-c", "import sys, numpy, scipy; print(sys.prefix)"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert check.returncode == 0, f"Virtual environment must contain NumPy and SciPy: {check.stderr}"
    assert os.path.realpath(check.stdout.strip()) == os.path.realpath("/home/user/perf_env"), (
        "perf_env/bin/python is not running from the requested virtual environment"
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Python script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a valid file"


def test_script_generates_correct_report():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    run_analysis()
    report_data = load_report()

    w_dist = report_data["wasserstein_distance"]
    ks_p = report_data["ks_p_value"]
    expected_w_dist = 5.7538
    expected_ks_p = 0.0
    assert abs(w_dist - expected_w_dist) <= 0.0002, (
        f"wasserstein_distance {w_dist} is not within acceptable range of {expected_w_dist}"
    )
    assert abs(ks_p - expected_ks_p) <= 0.0001, (
        f"ks_p_value {ks_p} is not within acceptable range of {expected_ks_p}"
    )

    with open(V1_PATH, "rb") as f:
        original_v1 = f.read()
    with open(V2_PATH, "rb") as f:
        original_v2 = f.read()

    rng = random.SystemRandom()
    sample1 = [rng.uniform(8.0, 35.0) for _ in range(37)]
    sample2 = [rng.uniform(11.0, 39.0) for _ in range(43)]

    try:
        with open(V1_PATH, "w") as f:
            f.writelines(f"{value:.8f}\n" for value in sample1)
        with open(V2_PATH, "w") as f:
            f.writelines(f"{value:.8f}\n" for value in sample2)

        expected = scipy_expected()
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_analysis()
        varied_report = load_report()

        assert varied_report["wasserstein_distance"] == pytest.approx(
            expected["wasserstein_distance"], abs=0.00005
        )
        assert varied_report["ks_p_value"] == pytest.approx(
            expected["ks_p_value"], abs=0.00005
        )
    finally:
        with open(V1_PATH, "wb") as f:
            f.write(original_v1)
        with open(V2_PATH, "wb") as f:
            f.write(original_v2)
        subprocess.run(
            [VENV_PYTHON, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
