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
import os
import csv
import math
import tempfile
import importlib.util
import importlib.metadata

import pytest
import requests
import numpy as np

DATA_PATH = "/home/user/data/artifacts.csv"
MATH_OPS_PATH = "/app/mlops-artifact-utils/mlops_artifact_utils/math_ops.py"
PLOT_OPS_PATH = "/app/mlops-artifact-utils/mlops_artifact_utils/plot_ops.py"
PLOT_PATH = "/home/user/artifact_clusters.png"
AUTH_HEADERS = {"Authorization": "Bearer mlops-secret-77"}


def read_artifacts():
    if not os.path.exists(DATA_PATH):
        pytest.fail(f"Data file is missing at {DATA_PATH}")

    artifacts = {}
    with open(DATA_PATH, "r", newline="") as f:
        for row in csv.DictReader(f):
            artifacts[row["artifact_id"]] = [float(row[f"f{i}"]) for i in range(1, 6)]
    return artifacts


def get_true_similarities(query_id):
    artifacts = read_artifacts()
    if query_id not in artifacts:
        pytest.fail(f"Query ID {query_id} not found in artifacts.csv")

    q_vec = artifacts[query_id]
    q_norm = math.sqrt(sum(x * x for x in q_vec))
    similarities = []
    for art_id, vec in artifacts.items():
        if art_id == query_id:
            continue
        dot = sum(x * y for x, y in zip(q_vec, vec))
        norm = math.sqrt(sum(x * x for x in vec))
        similarities.append((art_id, dot / (q_norm * norm)))

    similarities.sort(key=lambda x: x[1], reverse=True)
    return [x[0] for x in similarities[:3]]


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_cosine_implementation(function):
    X = np.array([
        [1.0, 0.0, 0.0],
        [0.0, 2.0, 0.0],
        [1.0, 1.0, 0.0],
        [-2.0, 0.0, 0.0],
        [1.0, 2.0, 3.0],
    ])
    norms = np.linalg.norm(X, axis=1)
    expected = (X @ X.T) / (norms[:, None] * norms[None, :])
    actual = np.asarray(function(X))
    assert actual.shape == expected.shape
    assert np.all(np.isfinite(actual)), "Cosine matrix contains non-finite values"
    assert np.allclose(actual, expected, rtol=1e-10, atol=1e-12), \
        f"Incorrect cosine similarity matrix:\n{actual}\nExpected:\n{expected}"


def read_png(path):
    assert os.path.isfile(path), f"Plot file is missing at {path}"
    assert os.path.getsize(path) > 0, "Plot file is empty"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "Plot is not a PNG file"
    import matplotlib.image as mpimg
    image = np.asarray(mpimg.imread(path))
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(np.std(image)) > 0.001, "Plot image is blank or visually constant"
    return image


def test_vendored_package_math_ops_fixed():
    assert os.path.isfile(MATH_OPS_PATH), f"math_ops.py missing at {MATH_OPS_PATH}"
    with open(MATH_OPS_PATH, "r") as f:
        content = f.read()
        assert "norms[:, np.newaxis] * norms[np.newaxis, :]" in content or \
               "*" in content and "+" not in content.split("return")[-1], \
               "Bug in math_ops.py (division by sum of norms) was not fixed correctly"

    source_module = load_module(MATH_OPS_PATH, "vendored_math_ops_check")
    assert_cosine_implementation(source_module.cosine_similarity_matrix)


def test_vendored_package_plot_ops_fixed_and_executable():
    assert os.path.isfile(PLOT_OPS_PATH), f"plot_ops.py missing at {PLOT_OPS_PATH}"
    with open(PLOT_OPS_PATH, "r") as f:
        content = f.read()
        assert "matplotlib.use('Agg')" in content or "matplotlib.use(\"Agg\")" in content, \
               "TkAgg backend setting in plot_ops.py was not changed to Agg"

    source_module = load_module(PLOT_OPS_PATH, "vendored_plot_ops_check")
    X = np.asarray(list(read_artifacts().values()), dtype=float)
    import matplotlib.pyplot as plt
    plt.close("all")
    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, "source_plot.png")
        source_module.plot_pca(X, output)
        read_png(output)
    plt.close("all")


def test_fixed_package_is_installed_and_functional():
    try:
        importlib.metadata.version("mlops-artifact-utils")
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("mlops-artifact-utils is not installed in the Python environment")

    import mlops_artifact_utils
    assert hasattr(mlops_artifact_utils, "cosine_similarity_matrix")
    assert hasattr(mlops_artifact_utils, "plot_pca")
    assert_cosine_implementation(mlops_artifact_utils.cosine_similarity_matrix)

    import matplotlib
    assert matplotlib.get_backend().lower() == "agg", \
        f"Installed package is not using the Agg backend: {matplotlib.get_backend()}"


def test_plot_exists_and_was_generated_by_installed_pipeline():
    actual = read_png(PLOT_PATH)

    import mlops_artifact_utils
    import matplotlib.pyplot as plt
    X = np.asarray(list(read_artifacts().values()), dtype=float)

    with tempfile.TemporaryDirectory() as td:
        expected_path = os.path.join(td, "expected.png")
        alternate_path = os.path.join(td, "alternate.png")

        plt.close("all")
        mlops_artifact_utils.plot_pca(X, expected_path)
        expected = read_png(expected_path)

        alternate_X = np.array([
            [0.0, 0.0, 0.0, 0.0, 0.0],
            [1.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0, 0.0],
            [1.0, 1.0, 0.0, 0.0, 0.0],
            [3.0, 0.2, 0.0, 0.0, 0.0],
        ])
        plt.close("all")
        mlops_artifact_utils.plot_pca(alternate_X, alternate_path)
        alternate = read_png(alternate_path)
        plt.close("all")

    assert actual.shape == expected.shape, "Saved plot has unexpected dimensions"
    assert np.array_equal(actual, expected), \
        "artifact_clusters.png does not match plot_pca output for artifacts.csv"
    assert expected.shape != alternate.shape or not np.array_equal(expected, alternate), \
        "plot_pca output does not respond to its input data"


def test_api_unauthorized():
    url = "http://127.0.0.1:8080/api/v1/similar?id=art_1"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized without auth, got {response.status_code}"


def test_api_wrong_auth():
    url = "http://127.0.0.1:8080/api/v1/similar?id=art_1"
    try:
        response = requests.get(url, headers={"Authorization": "Bearer wrong-secret"}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized with wrong auth, got {response.status_code}"


@pytest.mark.parametrize("query_id", list(read_artifacts().keys()))
def test_api_authorized_and_correct_for_every_artifact(query_id):
    url = "http://127.0.0.1:8080/api/v1/similar"
    try:
        response = requests.get(url, params={"id": query_id}, headers=AUTH_HEADERS, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 200, \
        f"Expected 200 OK for {query_id}, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "query_id" in data, "Response JSON missing 'query_id'"
    assert "top_3_similar" in data, "Response JSON missing 'top_3_similar'"
    assert data["query_id"] == query_id, \
        f"Expected query_id {query_id!r}, got {data['query_id']!r}"

    actual = data["top_3_similar"]
    expected = get_true_similarities(query_id)
    assert isinstance(actual, list), "top_3_similar must be a list"
    assert len(actual) == 3, f"Expected exactly 3 similar artifacts, got {len(actual)}"
    assert query_id not in actual, "The queried artifact must be excluded"
    assert len(set(actual)) == 3, "top_3_similar contains duplicate artifact IDs"
    assert actual == expected, \
        f"For {query_id}, expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
