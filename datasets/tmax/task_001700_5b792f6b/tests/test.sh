#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "annoy:annoy"; do
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
# test_final_state.py
import importlib.machinery
import importlib.metadata
import os

import numpy as np
import pandas as pd
from scipy.spatial.distance import cdist
import pytest


def test_annoy_installed():
    try:
        import annoy
        from annoy import AnnoyIndex
    except ImportError:
        pytest.fail("The 'annoy' library is not installed or failed to import. Did you fix setup.py and install it?")

    setup_path = '/app/annoy-1.17.3/setup.py'
    assert os.path.isfile(setup_path), f"File not found: {setup_path}"
    with open(setup_path, 'r', encoding='utf-8') as f:
        setup_contents = f.read()
    assert 'src/annoymodule.cc' in setup_contents, "setup.py does not reference src/annoymodule.cc"
    assert 'src/missing_module.cc' not in setup_contents, "setup.py still references the nonexistent source file"
    assert os.path.isfile('/app/annoy-1.17.3/src/annoymodule.cc')

    assert importlib.metadata.version('annoy') == '1.17.3', "The installed Annoy version is not 1.17.3"
    module_path = os.path.realpath(annoy.__file__)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"Imported annoy is not the compiled extension: {module_path}"

    # Exercise the repaired native package rather than accepting a merely importable stub.
    index = AnnoyIndex(2, 'euclidean')
    index.add_item(0, [0.0, 0.0])
    index.add_item(1, [1.0, 0.0])
    index.add_item(2, [0.0, 2.0])
    assert index.build(20)
    result = index.get_nns_by_vector([0.0, 0.0], 2)
    assert len(result) == 2 and result[0] == 0, "Installed Annoy extension is not functioning correctly"


def test_metric_recall_at_10():
    bootstrapped_path = '/home/user/bootstrapped_data.csv'
    neighbors_path = '/home/user/neighbors.csv'
    embeddings_path = '/home/user/embeddings.csv'

    assert os.path.exists(bootstrapped_path), f"File not found: {bootstrapped_path}"
    assert os.path.exists(neighbors_path), f"File not found: {neighbors_path}"
    assert os.path.exists(embeddings_path), f"File not found: {embeddings_path}"

    # 1. Reproduce the exact cleaned baseline data.
    raw_data = pd.read_csv(embeddings_path, header=None).values
    col_means = np.nanmean(raw_data, axis=0)
    nan_inds = np.where(np.isnan(raw_data))
    raw_data[nan_inds] = col_means[nan_inds[1]]
    cleaned_data = np.clip(raw_data, -2.0, 2.0)

    # 2. Reproduce the required seed-42 bootstrap sample.
    np.random.seed(42)
    expected_indices = np.random.choice(cleaned_data.shape[0], size=5000, replace=True)
    expected_bootstrapped_data = cleaned_data[expected_indices]

    # 3. Load the agent's bootstrapped data and neighbor predictions.
    bootstrapped_data = pd.read_csv(bootstrapped_path, header=None).values
    agent_neighbors = pd.read_csv(neighbors_path, header=None).values

    assert bootstrapped_data.shape == (5000, 50), f"Bootstrapped data shape is incorrect: {bootstrapped_data.shape}, expected (5000, 50)"
    assert agent_neighbors.shape == (100, 10), f"Neighbors file shape is incorrect: {agent_neighbors.shape}, expected (100, 10)"
    assert np.isfinite(bootstrapped_data).all(), "Bootstrapped data contains non-finite values"
    np.testing.assert_allclose(
        bootstrapped_data,
        expected_bootstrapped_data,
        rtol=1e-12,
        atol=1e-12,
        err_msg="bootstrapped_data.csv is not the required seed-42 sample of the cleaned embeddings",
    )

    assert np.isfinite(agent_neighbors).all(), "Neighbors file contains non-finite values"
    assert np.equal(agent_neighbors, np.floor(agent_neighbors)).all(), "Neighbor IDs must be integers"
    assert ((agent_neighbors >= 0) & (agent_neighbors < 5000)).all(), "Neighbor IDs must be in the range 0-4999"
    agent_neighbors = agent_neighbors.astype(np.int64)

    # 4. Compute exact brute-force nearest neighbors.
    query_data = cleaned_data[:100]
    distances = cdist(query_data, bootstrapped_data, metric='euclidean')

    recall_scores = []
    for i in range(100):
        # exact top 10
        exact_top_10 = set(np.argsort(distances[i])[:10])
        # agent top 10
        agent_top_10 = set(agent_neighbors[i])

        overlap = len(exact_top_10.intersection(agent_top_10))
        recall_scores.append(overlap / 10.0)

    mean_recall = np.mean(recall_scores)

    assert mean_recall >= 0.95, f"Metric failed: Recall@10 is {mean_recall:.4f}, expected >= 0.95"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
