#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
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
import math
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pytest
import requests


def derive_expected_result():
    config_path = Path("/app/config.png")
    source_path = Path("/home/user/sim.c")
    assert config_path.is_file(), f"Missing configuration image: {config_path}"
    assert source_path.is_file(), f"Missing simulation source: {source_path}"

    ocr_text = subprocess.run(
        ["tesseract", str(config_path), "stdout"],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout

    alpha_match = re.search(r"alpha\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", ocr_text, re.I)
    beta_match = re.search(r"beta\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", ocr_text, re.I)
    assert alpha_match and beta_match, f"Could not extract alpha and beta from OCR output: {ocr_text!r}"
    alpha = float(alpha_match.group(1))
    beta = float(beta_match.group(1))

    with tempfile.TemporaryDirectory() as tmpdir:
        executable = Path(tmpdir) / "sim"
        subprocess.run(
            ["gcc", str(source_path), "-O2", "-o", str(executable)],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = subprocess.run(
            [str(executable), format(alpha, ".17g"), format(beta, ".17g")],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout

    rows = []
    for line in output.splitlines():
        if not line.strip():
            continue
        fields = line.split()
        assert len(fields) == 2, f"Simulator emitted a malformed row: {line!r}"
        rows.append((float(fields[0]), float(fields[1])))
    assert rows, "Simulator emitted no data"

    values = np.asarray(rows, dtype=float)
    assert values.ndim == 2 and values.shape[1] == 2
    assert np.isfinite(values).all(), "Simulator output contains non-finite values"
    x = values[:, 0]
    y = values[:, 1]

    slope = float(np.polyfit(x, y, 1)[0])
    bootstrap_slopes = np.empty(1000, dtype=float)
    np.random.seed(123)
    for i in range(1000):
        indices = np.random.choice(len(x), size=len(x), replace=True)
        bootstrap_slopes[i] = np.polyfit(x[indices], y[indices], 1)[0]
    ci_lower, ci_upper = np.percentile(bootstrap_slopes, [2.5, 97.5])

    return {
        "slope": round(slope, 3),
        "ci_lower": round(float(ci_lower), 3),
        "ci_upper": round(float(ci_upper), 3),
    }


def test_api_result():
    expected = derive_expected_result()
    url = "http://127.0.0.1:8080/api/result"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    expected_keys = {"slope", "ci_lower", "ci_upper"}
    assert expected_keys.issubset(data.keys()), f"JSON response is missing required keys. Expected {expected_keys}, got {set(data.keys())}"
    assert set(data.keys()) == expected_keys, f"JSON response must contain exactly {expected_keys}, got {set(data.keys())}"

    slope = data["slope"]
    ci_lower = data["ci_lower"]
    ci_upper = data["ci_upper"]

    assert isinstance(slope, (int, float)), f"slope must be a number, got {type(slope)}"
    assert isinstance(ci_lower, (int, float)), f"ci_lower must be a number, got {type(ci_lower)}"
    assert isinstance(ci_upper, (int, float)), f"ci_upper must be a number, got {type(ci_upper)}"

    assert abs(slope - 3.140) <= 0.05, f"slope {slope} is not within tolerance of expected value ~3.140"
    assert abs(ci_lower - 3.100) <= 0.05, f"ci_lower {ci_lower} is not within tolerance of expected value ~3.100"
    assert abs(ci_upper - 3.180) <= 0.05, f"ci_upper {ci_upper} is not within tolerance of expected value ~3.180"
    assert ci_lower <= ci_upper, f"ci_lower {ci_lower} should be less than or equal to ci_upper {ci_upper}"

    for key in expected_keys:
        value = data[key]
        assert not isinstance(value, bool), f"{key} must be a JSON number, not a boolean"
        assert math.isfinite(value), f"{key} must be finite, got {value}"
        assert value == round(value, 3), f"{key} must be rounded to 3 decimal places, got {value}"
        assert value == expected[key], f"{key} is incorrect: expected {expected[key]}, got {value}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
