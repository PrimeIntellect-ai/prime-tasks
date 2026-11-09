#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.metrics import adjusted_rand_score

HOME = "/home/user"
DATA_DIR = os.path.join(HOME, "data")


def dataset_names():
    return sorted(os.path.basename(p) for p in glob.glob(os.path.join(DATA_DIR, "dataset_*.csv")))


def test_clusters_ari():
    clusters_file = os.path.join(HOME, "clusters.json")
    assert os.path.isfile(clusters_file), f"Agent's cluster output not found at {clusters_file}."

    with open(clusters_file, "r") as f:
        try:
            pred_dict = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{clusters_file} is not a valid JSON file.")

    assert isinstance(pred_dict, dict), "clusters.json must contain a dictionary."
    assert len(pred_dict) == 3, "clusters.json must contain exactly 3 clusters."

    names = dataset_names()
    assert len(names) == 30, "Expected exactly 30 input datasets."

    agent_mapping = {}
    submitted = []
    for c_id, files in pred_dict.items():
        assert isinstance(files, list), f"Cluster {c_id} must map to a list of filenames."
        for file in files:
            base = os.path.basename(file)
            assert base not in agent_mapping, f"File {base} appears in more than one cluster."
            agent_mapping[base] = c_id
            submitted.append(base)

    assert set(submitted) == set(names), "clusters.json must contain every dataset exactly once and no unknown files."

    for name in names:
        assert name in agent_mapping, f"File {name} is missing from the agent's clusters output."

    # The data generator assigns family i % 3. Derive this in the verifier rather
    # than exposing a ground-truth file in the agent image.
    y_true = [int(name.removeprefix("dataset_").removesuffix(".csv")) % 3 for name in names]
    y_pred = [agent_mapping[name] for name in names]
    ari = adjusted_rand_score(y_true, y_pred)
    assert ari >= 0.85, f"Adjusted Rand Index (ARI) is {ari:.4f}, which is below the threshold of 0.85."


def _expected_fastdtw_matrix(order):
    from fastdtw import fastdtw

    signals = []
    for name in order:
        values = pd.read_csv(os.path.join(DATA_DIR, name))["signal"].to_numpy(dtype=float)
        std = values.std()
        assert std > 0
        signals.append((values - values.mean()) / std)

    n = len(signals)
    matrix = np.zeros((n, n), dtype=float)
    for i in range(n):
        for j in range(i + 1, n):
            distance, _ = fastdtw(signals[i], signals[j])
            matrix[i, j] = matrix[j, i] = distance
    return matrix


def _load_matrix_candidates():
    excluded = {os.path.join(HOME, "clusters.json")}
    for path in glob.glob(os.path.join(HOME, "**", "*"), recursive=True):
        if not os.path.isfile(path) or path in excluded or path.startswith(DATA_DIR + os.sep):
            continue
        ext = os.path.splitext(path)[1].lower()
        try:
            arrays = []
            if ext == ".npy":
                arrays = [np.load(path, allow_pickle=False)]
            elif ext == ".npz":
                with np.load(path, allow_pickle=False) as archive:
                    arrays = [archive[key] for key in archive.files]
            elif ext in {".csv", ".txt", ".tsv"}:
                sep = "\t" if ext == ".tsv" else ("," if ext == ".csv" else None)
                for index_col in (None, 0):
                    try:
                        arrays.append(pd.read_csv(path, sep=sep, index_col=index_col).to_numpy(dtype=float))
                    except Exception:
                        pass
                try:
                    arrays.append(np.loadtxt(path, delimiter="," if ext == ".csv" else None))
                except Exception:
                    pass
            elif ext == ".json":
                with open(path) as f:
                    arrays = [np.asarray(json.load(f), dtype=float)]
            for array in arrays:
                array = np.asarray(array, dtype=float)
                if array.shape == (30, 30) and np.isfinite(array).all():
                    yield path, array
        except Exception:
            continue


def _matrix_matches(actual, expected):
    if not np.allclose(actual, actual.T, rtol=1e-5, atol=1e-5):
        return False
    if not np.allclose(np.diag(actual), 0, atol=1e-5):
        return False
    tri = np.triu_indices(30, 1)
    a = actual[tri]
    e = expected[tri]
    if np.any(a < 0) or np.ptp(a) == 0:
        return False
    correlation = np.corrcoef(a, e)[0, 1]
    scale = np.median(a / e)
    relative_mae = np.mean(np.abs(a - scale * e)) / np.mean(np.abs(scale * e))
    return np.isfinite(correlation) and correlation >= 0.98 and relative_mae <= 0.15


def test_real_dtw_distance_matrix_exists():
    lexical = dataset_names()
    numeric = sorted(lexical, key=lambda n: int(n.removeprefix("dataset_").removesuffix(".csv")))
    expected_matrices = [_expected_fastdtw_matrix(lexical)]
    if numeric != lexical:
        expected_matrices.append(_expected_fastdtw_matrix(numeric))

    candidates = list(_load_matrix_candidates())
    assert candidates, "No saved 30x30 numeric distance matrix was found under /home/user."
    assert any(_matrix_matches(matrix, expected) for _, matrix in candidates for expected in expected_matrices), \
        "No saved matrix matches normalized pairwise FastDTW distances."


def test_dendrogram_exists_and_script_runs():
    script = os.path.join(HOME, "plot_clusters.py")
    output = os.path.join(HOME, "dendrogram.png")
    assert os.path.isfile(script), f"{script} does not exist."

    with open(script, "r") as f:
        tree = ast.parse(f.read(), filename=script)
    calls = {
        node.func.id if isinstance(node.func, ast.Name) else node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, (ast.Name, ast.Attribute))
    }
    assert "dendrogram" in calls, "plot_clusters.py does not call scipy's dendrogram function."

    if os.path.exists(output):
        os.remove(output)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(
        [sys.executable, script], cwd=HOME, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120
    )
    assert result.returncode == 0, f"plot_clusters.py failed:\n{result.stdout}"
    assert os.path.isfile(output), f"{output} does not exist. Plotting script might have failed or not run."
    assert os.path.getsize(output) > 1000, "dendrogram.png is empty or implausibly small."

    from PIL import Image, ImageStat
    with Image.open(output) as image:
        image.verify()
    with Image.open(output).convert("RGB") as image:
        assert image.width >= 100 and image.height >= 100
        assert sum(ImageStat.Stat(image).var) > 0, "dendrogram.png is blank."


def test_fastdtw_installed():
    try:
        import fastdtw
        distance, path = fastdtw.fastdtw([0.0, 1.0, 2.0], [0.0, 1.0, 2.0])
        assert distance == pytest.approx(0.0)
        assert path
    except ImportError:
        pytest.fail("fastdtw package is not installed or importable. The package source might not be fixed.")

    setup_file = "/app/fastdtw-0.3.4/setup.py"
    assert os.path.isfile(setup_file), "The provided fastdtw package source is missing."
    with open(setup_file, "r") as f:
        assert "broken_environment_dependency_99" not in f.read(), "The injected setup.py import was not fixed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
