#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.base import BaseEstimator, TransformerMixin
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

DATASET = "/home/user/dataset.csv"
OUTPUT = "/home/user/best_model.json"
SELECTED_ARTIFACT = None
ORIGINAL_RESULT = None


class GroundTruthPCA(BaseEstimator, TransformerMixin):
    def __init__(self, n_components=3):
        self.n_components = n_components

    def fit(self, X, y=None):
        cov_mat = np.cov(X, rowvar=False)
        eigen_vals, eigen_vecs = np.linalg.eigh(cov_mat)
        sorted_indices = np.argsort(eigen_vals)[::-1]
        self.components_ = eigen_vecs[:, sorted_indices[:self.n_components]]
        return self

    def transform(self, X):
        return np.dot(X, self.components_)


def compute_truth(path=DATASET):
    df = pd.read_csv(path)
    X = df.drop(columns=[df.columns[-1]]).values
    y = df.iloc[:, -1].values
    pipeline = Pipeline([
        ('scaler', StandardScaler()),
        ('pca', GroundTruthPCA(n_components=3)),
        ('ridge', Ridge()),
    ])
    grid = GridSearchCV(
        pipeline,
        {'ridge__alpha': [0.1, 1.0, 10.0]},
        cv=KFold(n_splits=5, shuffle=True, random_state=42),
        scoring='neg_mean_squared_error',
    )
    grid.fit(X, y)
    return {
        'best_alpha': grid.best_params_['ridge__alpha'],
        'cv_mse': -grid.best_score_,
    }


def make_pca_blocker():
    blocker_dir = "/tmp/pca_blocker"
    os.makedirs(blocker_dir, exist_ok=True)
    with open(os.path.join(blocker_dir, "sitecustomize.py"), "w") as f:
        f.write(r'''
class _ForbiddenPCA:
    def __init__(self, *args, **kwargs):
        raise RuntimeError("Pre-packaged PCA/SVD estimators are forbidden; implement PCA with core linear algebra")

try:
    import sklearn.decomposition as _d
    for _name in ("PCA", "IncrementalPCA", "KernelPCA", "SparsePCA", "MiniBatchSparsePCA", "TruncatedSVD"):
        if hasattr(_d, _name):
            setattr(_d, _name, _ForbiddenPCA)
except Exception:
    pass

for _module_name in ("sklearn.decomposition._pca", "sklearn.decomposition._incremental_pca", "sklearn.decomposition._kernel_pca", "sklearn.decomposition._sparse_pca", "sklearn.decomposition._truncated_svd"):
    try:
        _m = __import__(_module_name, fromlist=["*"])
        for _name in ("PCA", "IncrementalPCA", "KernelPCA", "SparsePCA", "MiniBatchSparsePCA", "TruncatedSVD"):
            if hasattr(_m, _name):
                setattr(_m, _name, _ForbiddenPCA)
    except Exception:
        pass
''')
    return blocker_dir


def candidate_artifacts():
    candidates = []
    for pattern in ("/home/user/**/*.py", "/home/user/**/*.sh", "/home/user/**/*.ipynb"):
        candidates.extend(glob.glob(pattern, recursive=True))
    candidates = [p for p in candidates if os.path.isfile(p)]

    def score(path):
        points = 0
        try:
            text = open(path, "r", errors="ignore").read()
            if "best_model.json" in text:
                points += 10
            if "dataset.csv" in text:
                points += 5
            if "Ridge" in text or "ridge" in text:
                points += 2
        except OSError:
            pass
        return (-points, path)

    return sorted(set(candidates), key=score)


def command_for(path):
    if path.endswith(".py"):
        return [sys.executable, path]
    if path.endswith(".sh"):
        return ["bash", path]
    if path.endswith(".ipynb"):
        with open(path, "r") as f:
            notebook = json.load(f)
        code = []
        for cell in notebook.get("cells", []):
            if cell.get("cell_type") == "code":
                code.append("".join(cell.get("source", [])))
        extracted = "/tmp/submission_notebook.py"
        with open(extracted, "w") as f:
            f.write("\n\n".join(code))
        return [sys.executable, extracted]
    raise AssertionError("Unsupported artifact")


def run_artifact(path):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    env = os.environ.copy()
    blocker = make_pca_blocker()
    env["PYTHONPATH"] = blocker + os.pathsep + env.get("PYTHONPATH", "")
    completed = subprocess.run(
        command_for(path),
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"Submission artifact failed when executed with pre-packaged PCA disabled:\n"
        f"STDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}"
    )
    assert os.path.exists(OUTPUT), "Executing the submission did not create /home/user/best_model.json"
    with open(OUTPUT, "r") as f:
        return json.load(f)


def setup_module(module):
    global SELECTED_ARTIFACT, ORIGINAL_RESULT
    failures = []
    for artifact in candidate_artifacts():
        try:
            result = run_artifact(artifact)
            if isinstance(result, dict) and "best_alpha" in result and "cv_mse" in result:
                SELECTED_ARTIFACT = artifact
                ORIGINAL_RESULT = result
                return
        except Exception as exc:
            failures.append(f"{artifact}: {exc}")
    pytest.fail(
        "No executable implementation artifact was found that recreates best_model.json "
        "while sklearn's PCA estimators are disabled.\n" + "\n".join(failures)
    )


def test_json_output_exists():
    """Verify that the output JSON file was created."""
    assert os.path.exists(OUTPUT), "Output file /home/user/best_model.json does not exist."


def test_json_output_format():
    """Verify that the JSON file has the correct structure."""
    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("File /home/user/best_model.json is not valid JSON.")

    assert "best_alpha" in data, "Missing 'best_alpha' in JSON."
    assert "cv_mse" in data, "Missing 'cv_mse' in JSON."
    assert isinstance(data["best_alpha"], (int, float)), "'best_alpha' must be a number."
    assert isinstance(data["cv_mse"], (int, float)), "'cv_mse' must be a number."
    assert data["cv_mse"] > 0, "'cv_mse' must be positive."


def assert_matches(actual, truth, tolerance=1e-3):
    assert actual["best_alpha"] == truth["best_alpha"], (
        f"Alpha mismatch: Expected {truth['best_alpha']}, got {actual['best_alpha']}"
    )
    diff = abs(actual["cv_mse"] - truth["cv_mse"])
    assert diff / truth["cv_mse"] < tolerance, (
        f"MSE mismatch: Expected {truth['cv_mse']}, got {actual['cv_mse']}"
    )


def test_correct_values():
    """Verify that the computed best_alpha and cv_mse match the ground truth."""
    assert_matches(ORIGINAL_RESULT, compute_truth(), 1e-3)


def test_artifact_recomputes_with_fold_local_custom_pca():
    """Exercise the implementation on unseen data with packaged PCA disabled."""
    original_dataset = open(DATASET, "rb").read()
    original_output = open(OUTPUT, "rb").read()
    try:
        rng = np.random.RandomState(7319)
        n, p = 57, 9
        latent = rng.normal(size=(n, 5))
        mixing = rng.normal(size=(5, p))
        X = latent @ mixing + rng.normal(scale=0.08, size=(n, p))
        X[:6] += rng.normal(loc=4.0, scale=1.5, size=(6, p))
        y = 2.3 * X[:, 0] - 1.7 * X[:, 2] + 0.8 * X[:, 5] + rng.normal(scale=0.25, size=n)
        hidden = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(p)])
        hidden["target"] = y
        hidden.to_csv(DATASET, index=False)

        truth = compute_truth()
        actual = run_artifact(SELECTED_ARTIFACT)
        assert_matches(actual, truth, 2e-3)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
