#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest
import requests

CORE_PATH = "/app/prot_integrator/prot_integrator/core.py"
PDB_PATH = "/home/user/data/pdbs/1A2B.pdb"
NOTEBOOK_PATH = "/home/user/workflow.ipynb"
API_URL = "http://127.0.0.1:8080/api/v1/stats?pdb=1A2B"


def expected_simulation():
    # Independently reproduce the documented deterministic output sequence: the
    # integrator consumes one MT19937 draw per step, then returns a 10x10 array.
    rng = np.random.RandomState(42)
    rng.rand(1000)
    return rng.rand(10, 10)


def expected_bootstrap_ci(values):
    flat = np.asarray(values, dtype=float).ravel()
    rng = np.random.default_rng(20260911)
    indices = rng.integers(0, flat.size, size=(1000, flat.size))
    means = flat[indices].mean(axis=1)
    return np.percentile(means, [2.5, 97.5])


def test_prot_integrator_bug_fixed():
    assert os.path.isfile(CORE_PATH), f"Expected file {CORE_PATH} does not exist."
    with open(CORE_PATH, "r") as f:
        content = f.read()
    assert "dt = dt * 1.5" not in content and "dt *= 1.5" not in content, \
        f"The deliberate bug 'dt = dt * 1.5' is still present in {CORE_PATH}."


def test_installed_integrator_is_usable_and_numerically_correct():
    assert os.path.isfile(PDB_PATH), f"Expected input file {PDB_PATH} does not exist."
    script = r'''
import importlib.metadata
import json
import numpy as np
import prot_integrator

assert importlib.metadata.version("prot_integrator") == "1.2.0"
result = np.asarray(prot_integrator.simulate("/home/user/data/pdbs/1A2B.pdb", steps=1000))
print(json.dumps(result.tolist()))
'''
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    proc = subprocess.run(
        [sys.executable, "-c", script],
        cwd="/tmp",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"Installed package could not be executed:\n{proc.stderr}"
    try:
        result = np.asarray(json.loads(proc.stdout.strip().splitlines()[-1]), dtype=float)
    except Exception as exc:
        pytest.fail(f"Integrator did not produce a serializable numerical array: {exc}\n{proc.stdout}")

    expected = expected_simulation()
    assert result.shape == (10, 10), f"Expected simulation shape (10, 10), got {result.shape}."
    assert np.isfinite(result).all(), "The fixed integrator still diverges or returns non-finite values."
    np.testing.assert_allclose(result, expected, rtol=0, atol=1e-12)


def test_workflow_notebook_exists_and_executes_pipeline():
    assert os.path.isfile(NOTEBOOK_PATH), f"Expected Jupyter notebook {NOTEBOOK_PATH} does not exist."
    with open(NOTEBOOK_PATH, "r") as f:
        try:
            nb = json.load(f)
            assert "cells" in nb, f"File {NOTEBOOK_PATH} does not appear to be a valid Jupyter notebook."
        except json.JSONDecodeError:
            pytest.fail(f"File {NOTEBOOK_PATH} is not valid JSON.")

    code = "\n".join(
        cell.get("source", "") if isinstance(cell.get("source", ""), str)
        else "".join(cell.get("source", []))
        for cell in nb.get("cells", [])
        if cell.get("cell_type") == "code"
    )
    lower = code.lower()
    assert "prot_integrator" in code and "simulate" in code, \
        "Notebook must import and run prot_integrator.simulate."
    assert "1A2B.pdb" in code, "Notebook must run the simulation on 1A2B.pdb."
    assert "1000" in code, "Notebook must request 1000 simulation steps and bootstrap samples."
    assert ("bootstrap" in lower or "choice" in lower or "resample" in lower or "integers" in lower), \
        "Notebook must perform bootstrap resampling."
    assert ("percentile" in lower or "bootstrap" in lower), \
        "Notebook must compute a bootstrap confidence interval."
    assert "print" in lower, "Notebook must print the confidence interval results."

    proc = subprocess.run(
        [
            "jupyter", "nbconvert", "--to", "notebook", "--execute", NOTEBOOK_PATH,
            "--output", "workflow.executed.ipynb", "--output-dir", "/tmp",
            "--ExecutePreprocessor.timeout=120",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, f"Notebook failed to execute:\n{proc.stdout}\n{proc.stderr}"

    with open("/tmp/workflow.executed.ipynb", "r") as f:
        executed = json.load(f)
    outputs = [
        output
        for cell in executed.get("cells", [])
        if cell.get("cell_type") == "code"
        for output in cell.get("outputs", [])
    ]
    assert outputs, "Executed notebook did not print or display any results."


def get_api(headers=None):
    try:
        return requests.get(API_URL, headers=headers, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {API_URL}: {exc}")


def test_api_unauthorized_missing_token():
    response = get_api()
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized for missing token, got {response.status_code}."


def test_api_unauthorized_invalid_token():
    response = get_api({"Authorization": "Bearer wrong_token"})
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized for invalid token, got {response.status_code}."


def test_api_authorized_success_and_correct_statistics():
    response = get_api({"Authorization": "Bearer dev_token_99x"})
    assert response.status_code == 200, \
        f"Expected 200 OK for valid token, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "pdb_id" in data, "Response JSON missing 'pdb_id' key."
    assert data["pdb_id"] == "1A2B", f"Expected pdb_id '1A2B', got {data['pdb_id']}."
    assert "ci_lower" in data, "Response JSON missing 'ci_lower' key."
    assert "ci_upper" in data, "Response JSON missing 'ci_upper' key."
    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a number."
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a number."

    lower = float(data["ci_lower"])
    upper = float(data["ci_upper"])
    assert math.isfinite(lower) and math.isfinite(upper), "Confidence interval values must be finite."
    assert lower <= upper, "ci_lower must be less than or equal to ci_upper."

    expected_lower, expected_upper = expected_bootstrap_ci(expected_simulation())
    # Bootstrap endpoints vary slightly with the implementation and random seed;
    # this tolerance admits valid 1000-resample percentile/bootstrap intervals
    # while rejecting constants or intervals unrelated to the simulation.
    assert lower == pytest.approx(float(expected_lower), abs=0.02), \
        f"ci_lower {lower} is inconsistent with the simulated data (expected about {expected_lower})."
    assert upper == pytest.approx(float(expected_upper), abs=0.02), \
        f"ci_upper {upper} is inconsistent with the simulated data (expected about {expected_upper})."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
