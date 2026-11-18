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
import importlib.metadata
import json
import math
import os
import re
import signal
import subprocess
import time

import numpy as np
import pandas as pd
import pytest
import requests
from scipy import stats

API_URL = "http://127.0.0.1:8080"
HEADERS = {"Authorization": "Bearer ds-auth-token-999"}
MAIN_CSV = "/home/user/main_sensors.csv"
REF_CSV = "/home/user/ref_sensors.csv"
EXP_JSON = "/home/user/exp_results.json"
PIPELINE = "/home/user/pipeline.py"


def expected_results(path=MAIN_CSV):
    df = pd.read_csv(path)
    urban = df.loc[df["environment"] == "urban", "signal_strength"].to_numpy(dtype=float)
    rural = df.loc[df["environment"] == "rural", "signal_strength"].to_numpy(dtype=float)

    result = stats.ttest_ind(urban, rural, equal_var=False)
    difference = float(np.mean(urban) - np.mean(rural))
    var_u = float(np.var(urban, ddof=1))
    var_r = float(np.var(rural, ddof=1))
    term_u = var_u / len(urban)
    term_r = var_r / len(rural)
    standard_error = math.sqrt(term_u + term_r)
    degrees_freedom = (term_u + term_r) ** 2 / (
        term_u ** 2 / (len(urban) - 1) + term_r ** 2 / (len(rural) - 1)
    )
    margin = float(stats.t.ppf(0.975, degrees_freedom) * standard_error)

    columns = [f"feature_{i}" for i in range(1, 6)]
    matrix = df[columns].to_numpy(dtype=float)
    matrix -= matrix.mean(axis=0)
    _, _, vh = np.linalg.svd(matrix, full_matrices=False)

    return {
        "p_value": float(result.pvalue),
        "ci_lower": difference - margin,
        "ci_upper": difference + margin,
        "top_component": vh[0].astype(float),
    }


def numeric_values(value):
    values = []
    if isinstance(value, dict):
        for child in value.values():
            values.extend(numeric_values(child))
    elif isinstance(value, list):
        for child in value:
            values.extend(numeric_values(child))
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if math.isfinite(float(value)):
            values.append(float(value))
    return values


def numeric_vectors(value):
    vectors = []
    if isinstance(value, dict):
        for child in value.values():
            vectors.extend(numeric_vectors(child))
    elif isinstance(value, list):
        if len(value) == 5 and all(
            isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(float(x))
            for x in value
        ):
            vectors.append(np.asarray(value, dtype=float))
        for child in value:
            vectors.extend(numeric_vectors(child))
    return vectors


def assert_results_json(data, expected):
    assert isinstance(data, dict), "exp_results.json should contain a JSON object."
    scalars = numeric_values(data)
    for key in ("p_value", "ci_lower", "ci_upper"):
        target = expected[key]
        assert any(math.isclose(value, target, rel_tol=1e-6, abs_tol=5.1e-5) for value in scalars), (
            f"exp_results.json does not contain the correctly computed {key}."
        )

    target = expected["top_component"]
    vectors = numeric_vectors(data)
    assert any(
        np.allclose(vector, target, rtol=1e-6, atol=5.1e-5)
        or np.allclose(vector, -target, rtol=1e-6, atol=5.1e-5)
        for vector in vectors
    ), "exp_results.json does not contain the correctly computed first PCA component."


def load_exp_results():
    assert os.path.isfile(EXP_JSON), "exp_results.json is missing."
    with open(EXP_JSON, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("exp_results.json is not valid JSON.")


def test_exp_results_exists_and_is_correct():
    data = load_exp_results()
    assert_results_json(data, expected_results())


def test_api_unauthorized():
    try:
        r_pca = requests.get(f"{API_URL}/pca", timeout=5)
        r_test = requests.get(f"{API_URL}/test", timeout=5)
        r_bad = requests.get(
            f"{API_URL}/test", headers={"Authorization": "Bearer wrong-token"}, timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert r_pca.status_code == 401, f"Expected 401 for /pca without token, got {r_pca.status_code}"
    assert r_test.status_code == 401, f"Expected 401 for /test without token, got {r_test.status_code}"
    assert r_bad.status_code == 401, f"Expected 401 for an incorrect token, got {r_bad.status_code}"


def test_api_pca():
    try:
        r = requests.get(f"{API_URL}/pca", headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert r.status_code == 200, f"Expected 200 OK for /pca, got {r.status_code}. Body: {r.text}"
    data = r.json()
    assert "top_component" in data, "Response missing 'top_component' key."
    assert isinstance(data["top_component"], list), "'top_component' must be a list."
    assert len(data["top_component"]) == 5, f"Expected 5 elements in PCA vector, got {len(data['top_component'])}"
    for val in data["top_component"]:
        assert isinstance(val, (int, float)) and not isinstance(val, bool), "PCA vector elements must be numbers."
        assert math.isfinite(float(val)), "PCA vector elements must be finite."

    actual = np.asarray(data["top_component"], dtype=float)
    component = expected_results()["top_component"]
    positive = np.asarray([round(float(x), 4) for x in component])
    negative = np.asarray([round(float(-x), 4) for x in component])
    assert np.allclose(actual, positive, rtol=0, atol=1e-9) or np.allclose(actual, negative, rtol=0, atol=1e-9), (
        "The API PCA component does not match the centered input features rounded to 4 decimals."
    )


def test_api_test():
    try:
        r = requests.get(f"{API_URL}/test", headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert r.status_code == 200, f"Expected 200 OK for /test, got {r.status_code}. Body: {r.text}"
    data = r.json()
    expected = expected_results()
    for key in ["p_value", "ci_lower", "ci_upper"]:
        assert key in data, f"Response missing '{key}' key."
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), f"'{key}' must be a number."
        assert math.isfinite(float(data[key])), f"'{key}' must be finite."
        assert float(data[key]) == pytest.approx(round(expected[key], 4), rel=0, abs=1e-9), (
            f"'{key}' is not the Welch-test result derived from the supplied CSV, rounded to 4 decimals."
        )


def test_makefile_fixed():
    makefile_path = "/app/vendor/ml_prep_lib-0.1.0/Makefile"
    assert os.path.isfile(makefile_path), f"File {makefile_path} is missing."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "pip install ." in content, "Makefile does not contain the fixed 'pip install .' command."
    assert re.search(r"^[ \t]*pip install \.[ \t]*(?:#.*)?$", content, re.MULTILINE), (
        "The Makefile install recipe does not execute 'pip install .'."
    )
    assert not re.search(r"^[ \t]*pip[ \t]+intall\b", content, re.MULTILINE), (
        "The broken 'pip intall' recipe is still present."
    )


def test_core_py_fixed_and_installed():
    core_py_path = "/app/vendor/ml_prep_lib-0.1.0/ml_prep_lib/core.py"
    assert os.path.isfile(core_py_path), f"File {core_py_path} is missing."
    with open(core_py_path, "r") as f:
        content = f.read()
    assert "Int64" in content, "core.py does not seem to use 'Int64' to fix the precision loss issue."

    assert importlib.metadata.version("ml_prep_lib") == "0.1.0", "The fixed package is not installed."
    from ml_prep_lib.core import merge_sensor_data

    main = pd.DataFrame({
        "sensor_id": [1, 2, 3],
        "sensor_hash": [9007199254740993, 9007199254740995, 9007199254740999],
    })
    ref = pd.DataFrame({"sensor_id": [1, 3], "calibration_val": [0.99, 1.01]})
    merged = merge_sensor_data(main, ref)
    assert str(merged["sensor_hash"].dtype) == "Int64", (
        f"sensor_hash must use pandas nullable Int64 after merging, got {merged['sensor_hash'].dtype}."
    )
    assert merged["sensor_hash"].tolist() == [
        9007199254740993, 9007199254740995, 9007199254740999
    ], "merge_sensor_data did not preserve the 64-bit sensor hashes exactly."
    assert pd.isna(merged.loc[merged["sensor_id"] == 2, "calibration_val"]).all(), (
        "merge_sensor_data must retain unmatched main rows via a left merge."
    )


def test_pipeline_exists_and_recomputes_from_inputs():
    assert os.path.isfile(PIPELINE), "pipeline.py is missing."

    original_csv = open(MAIN_CSV, "rb").read()
    original_exp = open(EXP_JSON, "rb").read() if os.path.isfile(EXP_JSON) else None
    process = None
    try:
        changed = pd.read_csv(MAIN_CSV)
        changed["signal_strength"] = changed["signal_strength"] + np.asarray([2.3, -4.1, 7.7, 3.2, -6.4])
        for index, column in enumerate([f"feature_{i}" for i in range(1, 6)], start=1):
            changed[column] = changed[column] * (1.0 + index / 7.0) + np.arange(len(changed)) ** 2 / (index + 2)
        changed.to_csv(MAIN_CSV, index=False)
        expected = expected_results()

        if os.path.exists(EXP_JSON):
            os.unlink(EXP_JSON)
        process = subprocess.Popen(
            ["python3", PIPELINE],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.time() + 25
        data = None
        while time.time() < deadline:
            if os.path.isfile(EXP_JSON):
                try:
                    with open(EXP_JSON, "r") as f:
                        data = json.load(f)
                    break
                except (json.JSONDecodeError, OSError):
                    pass
            if process.poll() is not None and not os.path.isfile(EXP_JSON):
                break
            time.sleep(0.2)

        assert data is not None, "Executing pipeline.py did not produce a valid exp_results.json."
        assert_results_json(data, expected)
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except Exception:
                    pass
        with open(MAIN_CSV, "wb") as f:
            f.write(original_csv)
        if original_exp is not None:
            with open(EXP_JSON, "wb") as f:
                f.write(original_exp)
        elif os.path.exists(EXP_JSON):
            os.unlink(EXP_JSON)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
