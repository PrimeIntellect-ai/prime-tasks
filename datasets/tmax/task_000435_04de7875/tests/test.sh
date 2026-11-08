#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import tempfile
from pathlib import Path

import nbformat
import numpy as np
import pytest
import requests
from PIL import Image, ImageDraw, ImageFont
from nbconvert.preprocessors import ExecutePreprocessor

NOTEBOOK = Path("/home/user/gbm_sim.ipynb")
PARAMS_IMAGE = Path("/app/params.png")
HISTORICAL_CSV = Path("/app/historical.csv")


def test_notebook_exists():
    """Check if the Jupyter Notebook was created."""
    assert NOTEBOOK.is_file(), "The Jupyter Notebook /home/user/gbm_sim.ipynb was not created."


def _expected(params, prices):
    np.random.seed(params["Seed"])
    z = np.random.normal(0, 1, params["N_paths"])
    final_prices = params["S0"] * np.exp(
        (params["mu"] - params["sigma"] ** 2 / 2) * params["T"]
        + params["sigma"] * np.sqrt(params["T"]) * z
    )
    simulated_mean = float(np.mean(final_prices))
    reference_mean = float(np.mean(prices))
    return {
        **params,
        "simulated_mean": simulated_mean,
        "reference_mean": reference_mean,
        "difference": abs(simulated_mean - reference_mean),
    }


def _execute_and_probe(probe_path):
    notebook = nbformat.read(str(NOTEBOOK), as_version=4)
    assert notebook.cells, "The notebook is empty."
    code = "\n".join(cell.source for cell in notebook.cells if cell.cell_type == "code")
    assert code.strip(), "The notebook contains no Python code."
    assert "np.random.seed" in code, "The notebook must initialize NumPy with np.random.seed(Seed)."
    assert "np.random.normal" in code, "The notebook must draw paths with np.random.normal."
    assert "params.png" in code, "The notebook does not use /app/params.png."
    assert "historical.csv" in code, "The notebook does not use /app/historical.csv."

    probe_code = f'''
import json as _verifier_json

def _verifier_pick(*_names):
    for _name in _names:
        if _name in globals():
            return globals()[_name]
    raise AssertionError("Missing required result variable; tried: " + ", ".join(_names))

_verifier_result = {{
    "S0": int(_verifier_pick("S0", "s0")),
    "mu": float(_verifier_pick("mu")),
    "sigma": float(_verifier_pick("sigma")),
    "T": float(_verifier_pick("T", "t")),
    "Seed": int(_verifier_pick("Seed", "seed")),
    "N_paths": int(_verifier_pick("N_paths", "n_paths")),
    "simulated_mean": float(_verifier_pick("simulated_mean")),
    "reference_mean": float(_verifier_pick("reference_mean")),
    "difference": float(_verifier_pick("difference")),
}}
with open({str(probe_path)!r}, "w") as _verifier_file:
    _verifier_json.dump(_verifier_result, _verifier_file)
'''
    notebook.cells.append(nbformat.v4.new_code_cell(probe_code))
    executor = ExecutePreprocessor(timeout=180, kernel_name="python3", allow_errors=False)
    executor.preprocess(notebook, {"metadata": {"path": "/home/user"}})
    assert probe_path.is_file(), "Notebook execution did not produce its computed results."
    with probe_path.open() as f:
        return json.load(f)


def _assert_results(actual, expected):
    assert actual["S0"] == expected["S0"]
    assert math.isclose(actual["mu"], expected["mu"], abs_tol=1e-12)
    assert math.isclose(actual["sigma"], expected["sigma"], abs_tol=1e-12)
    assert math.isclose(actual["T"], expected["T"], abs_tol=1e-12)
    assert actual["Seed"] == expected["Seed"]
    assert actual["N_paths"] == expected["N_paths"]
    assert math.isclose(actual["simulated_mean"], expected["simulated_mean"], abs_tol=0.006)
    assert math.isclose(actual["reference_mean"], expected["reference_mean"], abs_tol=0.006)
    assert math.isclose(actual["difference"], expected["difference"], abs_tol=0.011)


def _write_parameter_image(params):
    image = Image.new("RGB", (520, 430), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
    text = (
        f'S0={params["S0"]}\n'
        f'mu={params["mu"]:.2f}\n'
        f'sigma={params["sigma"]:.2f}\n'
        f'T={params["T"]:.1f}\n'
        f'Seed={params["Seed"]}\n'
        f'N_paths={params["N_paths"]}'
    )
    draw.multiline_text((25, 25), text, fill="black", font=font, spacing=18)
    image.save(PARAMS_IMAGE)


def test_notebook_executes_real_workflow():
    original_params = PARAMS_IMAGE.read_bytes()
    original_csv = HISTORICAL_CSV.read_bytes()

    baseline_params = {"S0": 150, "mu": 0.08, "sigma": 0.15, "T": 2.0, "Seed": 42, "N_paths": 10000}
    baseline_prices = [165.20, 172.10, 168.50, 178.40, 169.30]

    token = secrets.token_hex(8)
    baseline_probe = Path(tempfile.gettempdir()) / f"gbm_probe_baseline_{token}.json"
    changed_probe = Path(tempfile.gettempdir()) / f"gbm_probe_changed_{token}.json"

    try:
        baseline = _execute_and_probe(baseline_probe)
        _assert_results(baseline, _expected(baseline_params, baseline_prices))

        changed_params = {
            "S0": secrets.randbelow(91) + 80,
            "mu": (secrets.randbelow(8) + 3) / 100.0,
            "sigma": (secrets.randbelow(14) + 11) / 100.0,
            "T": secrets.choice([1.0, 1.5, 2.5, 3.0]),
            "Seed": secrets.randbelow(8000) + 1000,
            "N_paths": secrets.randbelow(1501) + 2500,
        }
        changed_prices = [round(110 + secrets.randbelow(9000) / 100.0, 2) for _ in range(7)]
        _write_parameter_image(changed_params)
        HISTORICAL_CSV.write_text(
            "Final_Price\n" + "\n".join(f"{price:.2f}" for price in changed_prices) + "\n"
        )

        changed = _execute_and_probe(changed_probe)
        _assert_results(changed, _expected(changed_params, changed_prices))
    finally:
        PARAMS_IMAGE.write_bytes(original_params)
        HISTORICAL_CSV.write_bytes(original_csv)
        baseline_probe.unlink(missing_ok=True)
        changed_probe.unlink(missing_ok=True)


def test_http_server_metrics():
    """Check if the HTTP server is running and returning the correct metrics."""
    url = "http://127.0.0.1:8080/metrics"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}. Error: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("The response from /metrics is not valid JSON.")

    expected_keys = {"S0", "mu", "sigma", "simulated_mean", "reference_mean", "difference"}
    assert set(data.keys()) == expected_keys, f"Expected keys {expected_keys}, got {set(data.keys())}"

    assert data["S0"] == 150, f"Expected S0 to be 150, got {data['S0']}"
    assert math.isclose(data["mu"], 0.08, abs_tol=0.001), f"Expected mu to be 0.08, got {data['mu']}"
    assert math.isclose(data["sigma"], 0.15, abs_tol=0.001), f"Expected sigma to be 0.15, got {data['sigma']}"

    assert math.isclose(data["simulated_mean"], 175.76, abs_tol=0.02), f"Expected simulated_mean to be ~175.76, got {data['simulated_mean']}"
    assert math.isclose(data["reference_mean"], 170.70, abs_tol=0.02), f"Expected reference_mean to be ~170.70, got {data['reference_mean']}"
    assert math.isclose(data["difference"], 5.06, abs_tol=0.02), f"Expected difference to be ~5.06, got {data['difference']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
