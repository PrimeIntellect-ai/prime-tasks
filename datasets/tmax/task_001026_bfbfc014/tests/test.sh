#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

EDGES_PATH = "/home/user/edges.csv"
PAGERANKS_PATH = "/home/user/pageranks.csv"
TRAINING_PATH = "/home/user/training_data.csv"
DERIVE_PATH = "/home/user/derive_features.sh"
TOOLKIT_PATH = "/app/pagerank-awk-1.0/run_pagerank.sh"


def expected_edges_from_log():
    with open("/data/network_logs.txt", "r") as f:
        text = f.read()
    rows = []
    for block in re.split(r"^---\s*$", text, flags=re.MULTILINE):
        source = re.search(r"^Source:\s*(\S+)\s*$", block, flags=re.MULTILINE)
        target = re.search(r"^Target:\s*(\S+)\s*$", block, flags=re.MULTILINE)
        weight = re.search(r"^Weight:\s*(\S+)\s*$", block, flags=re.MULTILINE)
        if source or target or weight:
            assert source and target and weight, "Malformed observational log block."
            rows.append((int(source.group(1)), int(target.group(1)), float(weight.group(1))))
    return rows


def reference_pagerank(edges):
    nodes = sorted({s for s, _, _ in edges} | {t for _, t, _ in edges})
    n = len(nodes)
    out_degree = {node: 0.0 for node in nodes}
    edge = {}
    for source, target, weight in edges:
        out_degree[source] += weight
        edge[(source, target)] = weight

    d = 0.85
    pr = {node: 1.0 / n for node in nodes}
    for _ in range(50):
        new_pr = {node: (1.0 - d) / n for node in nodes}
        for source in nodes:
            if out_degree[source] > 0:
                for target in nodes:
                    if (source, target) in edge:
                        new_pr[target] += d * pr[source] * edge[(source, target)] / out_degree[source]
            else:
                for target in nodes:
                    new_pr[target] += d * pr[source] / n
        diff = sum((new_pr[node] - pr[node]) ** 2 for node in nodes)
        pr = new_pr
        if diff < 1e-6:
            break
    return pr


def read_pageranks(path):
    result = {}
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"{path} is empty."
    for row in rows:
        assert len(row) == 2, f"Invalid PageRank row in {path}: {row}"
        try:
            node = int(row[0])
            value = float(row[1])
        except ValueError as e:
            pytest.fail(f"Invalid numeric PageRank row in {path}: {row}: {e}")
        assert node not in result, f"Duplicate node {node} in {path}."
        assert math.isfinite(value), f"Non-finite PageRank for node {node}."
        result[node] = value
    return result


def assert_pageranks_match(actual, expected, atol=2e-6):
    assert set(actual) == set(expected), f"Incorrect PageRank node set: {set(actual)}; expected {set(expected)}."
    for node in expected:
        assert np.isclose(actual[node], expected[node], rtol=0, atol=atol), \
            f"Incorrect PageRank for node {node}: got {actual[node]}, expected {expected[node]}."


def exact_root(p):
    roots = np.roots([1, 0, 1, -p])
    return roots[np.isreal(roots)][0].real


def test_edges_csv():
    path = EDGES_PATH
    assert os.path.exists(path), f"File {path} does not exist."

    try:
        df = pd.read_csv(path)
    except Exception as e:
        pytest.fail(f"Failed to read {path} as CSV: {e}")

    expected_cols = ['source', 'target', 'weight']
    assert list(df.columns) == expected_cols, f"edges.csv columns are incorrect. Expected {expected_cols}, got {list(df.columns)}"
    assert len(df) == 4, f"edges.csv should have 4 rows, found {len(df)}."

    expected = expected_edges_from_log()
    try:
        actual = [(int(r.source), int(r.target), float(r.weight)) for r in df.itertuples(index=False)]
    except Exception as e:
        pytest.fail(f"edges.csv contains invalid values: {e}")
    assert actual == expected, f"edges.csv does not accurately represent /data/network_logs.txt. Got {actual}, expected {expected}."


def test_awk_bug_fixed():
    path = "/app/pagerank-awk-1.0/pr.awk"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "base = 1 - d" not in content.replace(" ", ""), f"The bug `base = 1 - d` is still present in {path}."
    assert "/N" in content, f"The fix dividing by N was not found in {path}."

    expected = reference_pagerank(expected_edges_from_log())
    proc = subprocess.run(
        [TOOLKIT_PATH, EDGES_PATH], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15
    )
    assert proc.returncode == 0, f"PageRank toolkit failed: {proc.stderr}"
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write(proc.stdout)
        tmp_path = tmp.name
    try:
        generated = read_pageranks(tmp_path)
    finally:
        os.unlink(tmp_path)
    assert_pageranks_match(generated, expected)


def test_pageranks_file_matches_graph():
    assert os.path.exists(PAGERANKS_PATH), f"File {PAGERANKS_PATH} does not exist."
    expected = reference_pagerank(expected_edges_from_log())
    assert_pageranks_match(read_pageranks(PAGERANKS_PATH), expected)


def test_derive_features_script_and_execute():
    assert os.path.isfile(DERIVE_PATH), f"File {DERIVE_PATH} does not exist or is not a regular file."

    backup = PAGERANKS_PATH + ".verifier_backup"
    shutil.copyfile(PAGERANKS_PATH, backup)
    try:
        # Exercise the submitted script on independently chosen values so a static
        # training_data.csv cannot pass.
        with open(PAGERANKS_PATH, "w") as f:
            f.write("9,0.05\n2,0.70\n5,0.25\n")
        if os.path.exists(TRAINING_PATH):
            os.unlink(TRAINING_PATH)
        proc = subprocess.run(["bash", DERIVE_PATH], text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15)
        assert proc.returncode == 0, f"derive_features.sh failed: {proc.stderr}"
        assert os.path.exists(TRAINING_PATH), "derive_features.sh did not create training_data.csv."
        challenge = pd.read_csv(TRAINING_PATH)
        assert list(challenge.columns) == ['Node', 'PageRank', 'Derived_X']
        assert list(challenge['Node']) == [2, 5, 9], "derive_features.sh did not sort challenge nodes numerically."
        expected_p = {2: 0.70, 5: 0.25, 9: 0.05}
        for row in challenge.itertuples(index=False):
            assert np.isclose(float(row.PageRank), expected_p[int(row.Node)], atol=1e-12)
            assert abs(float(row.Derived_X) - exact_root(expected_p[int(row.Node)])) <= 1e-4
    finally:
        shutil.move(backup, PAGERANKS_PATH)

    if os.path.exists(TRAINING_PATH):
        os.unlink(TRAINING_PATH)
    proc = subprocess.run(["bash", DERIVE_PATH], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=15)
    assert proc.returncode == 0, f"derive_features.sh failed on the supplied graph: {proc.stderr}"
    assert os.path.exists(TRAINING_PATH), "derive_features.sh did not create final training_data.csv."


def test_training_data_metric():
    path = TRAINING_PATH
    assert os.path.exists(path), f"File {path} does not exist."

    try:
        df = pd.read_csv(path)
    except Exception as e:
        pytest.fail(f"Failed to read {path}: {e}")

    expected_cols = ['Node', 'PageRank', 'Derived_X']
    assert list(df.columns) == expected_cols, f"Incorrect columns in {path}. Expected {expected_cols}, got {list(df.columns)}."

    # Check sorting by Node ID (original assertion).
    assert df['Node'].is_monotonic_increasing, "The rows in training_data.csv must be sorted numerically by Node ID."

    for col in expected_cols:
        assert pd.api.types.is_numeric_dtype(df[col]), f"Column {col} must be numeric."
        assert np.isfinite(df[col].to_numpy(dtype=float)).all(), f"Column {col} contains non-finite values."

    expected_pr = reference_pagerank(expected_edges_from_log())
    expected_nodes = sorted(expected_pr)
    assert df['Node'].astype(int).tolist() == expected_nodes, \
        f"Incorrect training node set; expected {expected_nodes}."
    assert len(df) == len(expected_nodes), "training_data.csv has an incorrect number of rows."
    for row in df.itertuples(index=False):
        node = int(row.Node)
        assert np.isclose(float(row.PageRank), expected_pr[node], rtol=0, atol=2e-6), \
            f"PageRank for node {node} does not match the supplied graph."

    # Check that PageRanks sum to 1.0 (original assertion).
    sum_pr = df['PageRank'].sum()
    assert np.isclose(sum_pr, 1.0, atol=1e-3), f"PageRanks sum to {sum_pr}, expected 1.0. The awk bug might not be properly fixed or script wasn't re-run."

    # Re-derive the exact roots (original metric).
    df['Expected_X'] = df['PageRank'].apply(exact_root)
    mae = np.max(np.abs(df['Derived_X'] - df['Expected_X']))

    threshold = 1e-4
    assert mae <= threshold, f"FAIL: MAE {mae} > {threshold}. The derived features are not accurate enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
