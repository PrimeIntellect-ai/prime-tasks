#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import subprocess

import pytest

VENV_PYTHON = '/home/user/venv/bin/python'
SCRIPT_PATH = '/home/user/run_analysis.py'
DATA_PATH = '/home/user/sensor_data.csv'
LOG_PATH = '/home/user/experiment_log.json'
EXPECTED = None


@pytest.fixture(scope='session', autouse=True)
def execute_and_verify_artifact():
    global EXPECTED

    assert os.path.exists(VENV_PYTHON), f"Virtual environment Python not found at {VENV_PYTHON}"
    assert os.path.isfile(SCRIPT_PATH), f"Analysis script not found at {SCRIPT_PATH}"
    assert os.path.isfile(DATA_PATH), f"Sensor dataset not found at {DATA_PATH}"

    with open(DATA_PATH, 'rb') as f:
        data_hash_before = hashlib.sha256(f.read()).hexdigest()

    reference_code = r'''
import json
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.mixture import BayesianGaussianMixture

X = pd.read_csv('/home/user/sensor_data.csv')
X_scaled = StandardScaler().fit_transform(X)
pca = PCA(n_components=3, random_state=42)
X_pca = pca.fit_transform(X_scaled)
bgm = BayesianGaussianMixture(n_components=5, max_iter=500, random_state=42)
bgm.fit(X_pca)
print(json.dumps({
    "pca_explained_variance_ratio_sum": float(pca.explained_variance_ratio_.sum()),
    "bgm_lower_bound": float(bgm.lower_bound_),
    "bgm_converged": bool(bgm.converged_),
}))
'''
    reference = subprocess.run(
        [VENV_PYTHON, '-c', reference_code],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert reference.returncode == 0, (
        f"Failed to independently compute expected analysis results: {reference.stderr}"
    )
    EXPECTED = json.loads(reference.stdout.strip())

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        [VENV_PYTHON, SCRIPT_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"run_analysis.py failed with exit code {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), "run_analysis.py did not generate experiment_log.json"

    with open(DATA_PATH, 'rb') as f:
        data_hash_after = hashlib.sha256(f.read()).hexdigest()
    assert data_hash_after == data_hash_before, "run_analysis.py modified sensor_data.csv"


def test_venv_exists():
    venv_python = '/home/user/venv/bin/python'
    assert os.path.exists(venv_python), f"Virtual environment Python not found at {venv_python}"


def test_dependencies_installed():
    venv_python = '/home/user/venv/bin/python'
    assert os.path.exists(venv_python), "Virtual environment not found."

    result = subprocess.run(
        [venv_python, '-c', 'import sklearn; print(sklearn.__version__)'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to import sklearn in the venv."
    assert result.stdout.strip() == "1.3.2", f"Expected scikit-learn==1.3.2, but got {result.stdout.strip()}"

    result_pd = subprocess.run(
        [venv_python, '-c', 'import pandas'],
        capture_output=True, text=True
    )
    assert result_pd.returncode == 0, "Failed to import pandas in the venv."


def test_script_exists():
    script_path = '/home/user/run_analysis.py'
    assert os.path.exists(script_path), f"Analysis script not found at {script_path}"


def test_experiment_log_valid():
    log_path = '/home/user/experiment_log.json'
    assert os.path.exists(log_path), f"Experiment log not found at {log_path}"

    with open(log_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "Experiment log is not valid JSON."

    assert "pca_explained_variance_ratio_sum" in data, "Missing 'pca_explained_variance_ratio_sum' in log."
    assert "bgm_lower_bound" in data, "Missing 'bgm_lower_bound' in log."
    assert "bgm_converged" in data, "Missing 'bgm_converged' in log."
    assert set(data) == {
        "pca_explained_variance_ratio_sum",
        "bgm_lower_bound",
        "bgm_converged",
    }, "Experiment log must contain exactly the requested fields."

    assert data["bgm_converged"] is True, f"Expected bgm_converged to be True, got {data['bgm_converged']}"

    pca_var = data["pca_explained_variance_ratio_sum"]
    assert isinstance(pca_var, float), "pca_explained_variance_ratio_sum must be a float."
    assert 0.70 < pca_var < 0.80, f"pca_explained_variance_ratio_sum {pca_var} is out of expected range (0.70 - 0.80)."

    bgm_lb = data["bgm_lower_bound"]
    assert isinstance(bgm_lb, float), "bgm_lower_bound must be a float."
    assert -5.0 < bgm_lb < -3.0, f"bgm_lower_bound {bgm_lb} is out of expected range (-5.0 - -3.0)."

    assert data["bgm_converged"] is EXPECTED["bgm_converged"], (
        "Logged convergence status does not match an independent recomputation."
    )
    assert math.isclose(
        pca_var,
        EXPECTED["pca_explained_variance_ratio_sum"],
        rel_tol=1e-9,
        abs_tol=1e-12,
    ), "Logged PCA explained variance does not match an independent recomputation."
    assert math.isclose(
        bgm_lb,
        EXPECTED["bgm_lower_bound"],
        rel_tol=1e-9,
        abs_tol=1e-12,
    ), "Logged BayesianGaussianMixture lower bound does not match an independent recomputation."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
