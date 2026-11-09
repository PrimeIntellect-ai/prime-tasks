#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pickle
import subprocess

import numpy as np
import pandas as pd
import pytest
from PIL import Image
from sklearn.decomposition import PCA
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.preprocessing import StandardScaler

DATA_PATH = '/app/data/user_engagement.csv'
PRED_PATH = '/home/user/top_100_similar.csv'
TRUTH_PATH = '/tests/truth.csv'
SCRIPT_PATH = '/app/scripts/generate_plot.py'
PLOT_PATH = '/home/user/pca_plot.png'
TARGET_ID = 7392


def canonical_results(n_components=10):
    df = pd.read_csv(DATA_PATH)
    feature_cols = [c for c in df.columns if c != 'user_id' and not c.startswith('legacy_')]
    x = StandardScaler().fit_transform(df[feature_cols].to_numpy())
    projected = PCA(n_components=n_components, random_state=42).fit_transform(x)
    target_matches = np.flatnonzero(df['user_id'].to_numpy() == TARGET_ID)
    assert len(target_matches) == 1, 'Target user must occur exactly once in the dataset.'
    target_idx = int(target_matches[0])
    similarities = cosine_similarity(projected[target_idx:target_idx + 1], projected).ravel()
    similarities[target_idx] = -np.inf
    order = np.argsort(similarities)[::-1][:100]
    return df, projected, order, similarities


def test_recall_metric_and_similarity_output():
    assert os.path.exists(PRED_PATH), f'Output file missing: {PRED_PATH}'
    try:
        pred_df = pd.read_csv(PRED_PATH)
    except Exception as exc:
        pytest.fail(f'Could not read {PRED_PATH} as CSV: {exc}')

    assert list(pred_df.columns) == ['user_id', 'similarity_score'], \
        "Output CSV must contain exactly the columns 'user_id' and 'similarity_score' in that order."
    assert len(pred_df) == 100, 'Output CSV must contain exactly 100 users.'
    assert pred_df['user_id'].notna().all() and pred_df['similarity_score'].notna().all()
    assert pd.api.types.is_numeric_dtype(pred_df['user_id'])
    assert pd.api.types.is_numeric_dtype(pred_df['similarity_score'])
    assert np.isfinite(pred_df['similarity_score'].to_numpy(dtype=float)).all()
    assert pred_df['user_id'].is_unique, 'Output contains duplicate user IDs.'
    assert TARGET_ID not in set(pred_df['user_id']), 'The target user must be excluded.'
    assert pred_df['similarity_score'].is_monotonic_decreasing, \
        'Rows must be sorted by descending similarity_score.'

    assert os.path.exists(TRUTH_PATH), f'Truth file missing from verifier bundle: {TRUTH_PATH}'
    truth_df = pd.read_csv(TRUTH_PATH)
    pred_users = set(pred_df['user_id'].to_numpy())
    truth_users = set(truth_df['user_id'].to_numpy())
    recall = len(pred_users.intersection(truth_users)) / 100.0
    assert recall >= 0.95, f'Recall@100 is {recall}, which is below the threshold of 0.95.'

    df, _, order, similarities = canonical_results(10)
    valid_ids = set(df['user_id'].to_numpy())
    assert pred_users <= valid_ids, 'Output contains user IDs not present in the dataset.'
    expected_scores = pd.Series(similarities, index=df['user_id'].to_numpy())
    submitted_expected = expected_scores.loc[pred_df['user_id'].to_numpy()].to_numpy()
    np.testing.assert_allclose(
        pred_df['similarity_score'].to_numpy(dtype=float),
        submitted_expected,
        rtol=1e-6,
        atol=1e-7,
        err_msg='Submitted similarity scores do not match the required 10-component PCA cosine similarities.'
    )


def test_plot_script_fixes_and_uses_dataset_pca():
    assert os.path.exists(SCRIPT_PATH), f'Plotting script missing: {SCRIPT_PATH}'
    if os.path.exists(PLOT_PATH):
        os.remove(PLOT_PATH)

    result = subprocess.run(['python3', SCRIPT_PATH], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f'Script failed to run. Stderr: {result.stderr}'
    assert os.path.exists(PLOT_PATH), f'Plot image was not created at {PLOT_PATH} after running the script.'

    try:
        img = Image.open(PLOT_PATH).convert('RGB')
        extrema = img.getextrema()
    except Exception as exc:
        pytest.fail(f'Could not open {PLOT_PATH} as an image: {exc}')
    assert not all(lo == hi for lo, hi in extrema), 'The generated plot image is completely blank.'

    capture_path = '/tmp/scatter_capture.pkl'
    harness_path = '/tmp/run_plot_instrumented.py'
    with open(harness_path, 'w') as handle:
        handle.write(r'''import os, pickle, runpy
import numpy as np
import matplotlib
matplotlib.use('Agg')
from matplotlib.axes import Axes

captures = []
_original_scatter = Axes.scatter

def recording_scatter(self, x, y, *args, **kwargs):
    try:
        xa = np.asarray(x, dtype=float).reshape(-1)
        ya = np.asarray(y, dtype=float).reshape(-1)
        if xa.size == ya.size:
            captures.append(np.column_stack((xa, ya)))
    except Exception:
        pass
    return _original_scatter(self, x, y, *args, **kwargs)

Axes.scatter = recording_scatter
runpy.run_path('/app/scripts/generate_plot.py', run_name='__main__')
with open('/tmp/scatter_capture.pkl', 'wb') as output:
    pickle.dump(captures, output)
''')
    if os.path.exists(capture_path):
        os.remove(capture_path)
    instrumented = subprocess.run(['python3', harness_path], capture_output=True, text=True, timeout=60)
    assert instrumented.returncode == 0, \
        f'Could not inspect the scatter plot produced by the script. Stderr: {instrumented.stderr}'
    assert os.path.exists(capture_path), 'The plotting script did not produce an inspectable scatter plot.'
    with open(capture_path, 'rb') as handle:
        captures = pickle.load(handle)

    df = pd.read_csv(DATA_PATH)
    feature_cols = [c for c in df.columns if c != 'user_id' and not c.startswith('legacy_')]
    scaled = StandardScaler().fit_transform(df[feature_cols].to_numpy())
    expected = PCA(n_components=2, random_state=42).fit_transform(scaled)

    def sorted_cloud(points):
        return points[np.lexsort((points[:, 1], points[:, 0]))]

    actual_clouds = [np.asarray(c, dtype=float) for c in captures if np.asarray(c).shape == expected.shape]
    matched = False
    for actual in actual_clouds:
        for swap in (False, True):
            base = expected[:, ::-1] if swap else expected
            for sx in (-1.0, 1.0):
                for sy in (-1.0, 1.0):
                    candidate = base * np.array([sx, sy])
                    if np.allclose(sorted_cloud(actual), sorted_cloud(candidate), rtol=1e-5, atol=1e-5):
                        matched = True
                        break
                if matched:
                    break
            if matched:
                break
        if matched:
            break

    assert matched, \
        'The scatter plot must visualize the dataset PCA projection after dropping legacy_ columns and standardizing features.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
