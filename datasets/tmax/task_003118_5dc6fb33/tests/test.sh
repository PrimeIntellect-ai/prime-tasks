#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
from scipy.optimize import least_squares

DATA_PATH = "/home/user/drug_data.csv"
RESULT_PATH = "/home/user/results.json"
EXPECTED_KEYS = ["k1", "k2", "auc_plasma", "kl_divergence"]


def model_values(times, k1, k2):
    rate = k1 + k2
    steady_plasma = k2 / rate
    plasma = steady_plasma + (1.0 - steady_plasma) * np.exp(-rate * times)
    return np.column_stack((plasma, 1.0 - plasma))


def reference_results(csv_bytes):
    frame = pd.read_csv(io.BytesIO(csv_bytes))
    assert list(frame.columns) == ["time", "plasma_conc", "tissue_conc"]
    times = frame["time"].to_numpy(dtype=float)
    observed = frame[["plasma_conc", "tissue_conc"]].to_numpy(dtype=float)

    def residual(params):
        return (model_values(times, params[0], params[1]) - observed).ravel()

    fit = least_squares(residual, x0=np.array([0.4, 0.3]), bounds=(1e-10, np.inf),
                        xtol=1e-13, ftol=1e-13, gtol=1e-13, max_nfev=20000)
    assert fit.success
    k1, k2 = map(float, fit.x)
    rate = k1 + k2
    p_plasma = k2 / rate
    p_tissue = k1 / rate
    auc = p_plasma * 50.0 + (k1 / rate) * (1.0 - math.exp(-rate * 50.0)) / rate
    kl = p_plasma * math.log(p_plasma / 0.3) + p_tissue * math.log(p_tissue / 0.7)
    return {"k1": k1, "k2": k2, "auc_plasma": auc, "kl_divergence": kl}


def load_result():
    assert os.path.exists(RESULT_PATH), f"The file {RESULT_PATH} does not exist."
    assert os.path.isfile(RESULT_PATH), f"The path {RESULT_PATH} is not a file."
    with open(RESULT_PATH, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            raise AssertionError(f"The file {RESULT_PATH} does not contain valid JSON.")
    for key in EXPECTED_KEYS:
        assert key in data, f"Missing key '{key}' in {RESULT_PATH}."
        assert isinstance(data[key], (int, float)), f"Value for '{key}' must be a number."
        assert math.isfinite(float(data[key])), f"Value for '{key}' must be finite."
    return data


def check_original_assertions(data):
    k1 = data["k1"]
    k2 = data["k2"]
    auc_plasma = data["auc_plasma"]
    kl_divergence = data["kl_divergence"]
    assert 0.48 <= k1 <= 0.52, f"k1 value {k1} is out of expected bounds [0.48, 0.52]."
    assert 0.18 <= k2 <= 0.22, f"k2 value {k2} is out of expected bounds [0.18, 0.22]."
    assert 15.1 <= auc_plasma <= 15.5, f"auc_plasma value {auc_plasma} is out of expected bounds [15.1, 15.5]."
    assert 0.0001 <= kl_divergence <= 0.002, f"kl_divergence value {kl_divergence} is out of expected bounds [0.0001, 0.002]."


def check_against_reference(data, expected):
    assert abs(float(data["k1"]) - expected["k1"]) <= 8e-4
    assert abs(float(data["k2"]) - expected["k2"]) <= 8e-4
    assert abs(float(data["auc_plasma"]) - expected["auc_plasma"]) <= 3e-3
    assert abs(float(data["kl_divergence"]) - expected["kl_divergence"]) <= 2e-4


def find_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
        for name in files:
            if name.endswith(".py"):
                path = os.path.join(root, name)
                if os.path.isfile(path):
                    scripts.append(path)
    scripts.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return scripts


def run_script(path):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    compile(open(path, "rb").read(), path, "exec")
    completed = subprocess.run(
        ["python3", path], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90
    )
    assert completed.returncode == 0, (
        f"Script {path} failed. stdout={completed.stdout!r} stderr={completed.stderr!r}"
    )
    return load_result()


def test_analysis_script_and_results():
    with open(DATA_PATH, "rb") as handle:
        original_csv = handle.read()
    initial_result = None
    if os.path.isfile(RESULT_PATH):
        with open(RESULT_PATH, "rb") as handle:
            initial_result = handle.read()

    expected_original = reference_results(original_csv)

    # Use a fresh, undisclosed positive-rate dataset to ensure the submitted script
    # actually reads and fits drug_data.csv rather than emitting fixed constants.
    k1_challenge = 0.25 + secrets.randbelow(400000) / 1000000.0
    k2_challenge = 0.12 + secrets.randbelow(350000) / 1000000.0
    times = np.linspace(0.0, 10.0, 50)
    values = model_values(times, k1_challenge, k2_challenge)
    challenge_frame = pd.DataFrame({
        "time": times,
        "plasma_conc": values[:, 0],
        "tissue_conc": values[:, 1],
    })
    challenge_csv = challenge_frame.to_csv(index=False).encode()
    expected_challenge = reference_results(challenge_csv)

    accepted_result = None
    errors = []
    try:
        scripts = find_scripts()
        assert scripts, "No Python analysis script was found under /home/user."

        for script in scripts:
            try:
                with open(DATA_PATH, "wb") as handle:
                    handle.write(original_csv)
                original_output = run_script(script)
                check_original_assertions(original_output)
                check_against_reference(original_output, expected_original)
                with open(RESULT_PATH, "rb") as handle:
                    original_output_bytes = handle.read()

                with open(DATA_PATH, "wb") as handle:
                    handle.write(challenge_csv)
                challenge_output = run_script(script)
                check_against_reference(challenge_output, expected_challenge)

                accepted_result = original_output_bytes
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")

        assert accepted_result is not None, "No submitted Python script passed execution and fitting checks: " + " | ".join(errors)
    finally:
        with open(DATA_PATH, "wb") as handle:
            handle.write(original_csv)
        restore = accepted_result if accepted_result is not None else initial_result
        if restore is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as handle:
                handle.write(restore)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
