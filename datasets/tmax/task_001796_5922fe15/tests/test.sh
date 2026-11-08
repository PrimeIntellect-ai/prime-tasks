#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
os.environ['MPLBACKEND'] = 'Agg'

import json
import math
import runpy
import numpy as np
import pandas as pd
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity


def calculate_truth():
    experiments = pd.read_csv('/home/user/experiments.csv')
    feedback = pd.read_csv('/home/user/feedback.csv')
    joined = experiments.merge(feedback, on='user_id')

    durations_a = joined.loc[joined['group'] == 'A', 'session_duration'].to_numpy()
    durations_b = joined.loc[joined['group'] == 'B', 'session_duration'].to_numpy()

    np.random.seed(42)
    bootstrap_differences = []
    for _ in range(1000):
        sample_a = np.random.choice(durations_a, size=len(durations_a), replace=True)
        sample_b = np.random.choice(durations_b, size=len(durations_b), replace=True)
        bootstrap_differences.append(float(np.mean(sample_b) - np.mean(sample_a)))
    bootstrap_differences = np.asarray(bootstrap_differences)

    group_b = joined[joined['group'] == 'B']
    successes = int(group_b['conversion'].sum())
    posterior_mean = (1 + successes) / (2 + len(group_b))

    candidates = joined[(joined['group'] == 'B') & (joined['conversion'] == 1)]
    assert len(candidates) > 0, 'No converted Group B users are available.'
    vectorizer = TfidfVectorizer()
    embeddings = vectorizer.fit_transform(candidates['feedback_text'])
    query_embedding = vectorizer.transform(['fast checkout'])
    similarities = cosine_similarity(query_embedding, embeddings).ravel()
    most_similar_user_id = int(candidates.iloc[int(np.argmax(similarities))]['user_id'])

    truth = {
        'ci_lower': round(float(np.percentile(bootstrap_differences, 2.5)), 4),
        'ci_upper': round(float(np.percentile(bootstrap_differences, 97.5)), 4),
        'posterior_mean': round(float(posterior_mean), 4),
        'most_similar_user_id': most_similar_user_id,
    }
    return truth, bootstrap_differences


def test_results_json_exists_and_format():
    results_path = '/home/user/results.json'
    assert os.path.exists(results_path), f'The file {results_path} is missing.'
    assert os.path.isfile(results_path), f'{results_path} is not a file.'

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{results_path} is not a valid JSON file.')

    expected_keys = {'ci_lower', 'ci_upper', 'posterior_mean', 'most_similar_user_id'}
    assert set(results.keys()) == expected_keys, f'JSON keys do not match expected keys. Found: {list(results.keys())}'

    assert isinstance(results['ci_lower'], (int, float)), 'ci_lower must be a number'
    assert isinstance(results['ci_upper'], (int, float)), 'ci_upper must be a number'
    assert isinstance(results['posterior_mean'], (int, float)), 'posterior_mean must be a number'
    assert isinstance(results['most_similar_user_id'], int), 'most_similar_user_id must be an integer'
    assert all(math.isfinite(float(results[k])) for k in ('ci_lower', 'ci_upper', 'posterior_mean'))
    assert all(results[k] == round(results[k], 4) for k in ('ci_lower', 'ci_upper', 'posterior_mean')), 'Numeric results must be rounded to 4 decimal places.'


def test_results_values_match_truth():
    results_path = '/home/user/results.json'
    truth, _ = calculate_truth()

    with open(results_path, 'r') as f:
        results = json.load(f)

    assert abs(results['ci_lower'] - truth['ci_lower']) < 1e-3, f"ci_lower is incorrect. Expected approx {truth['ci_lower']}, got {results['ci_lower']}"
    assert abs(results['ci_upper'] - truth['ci_upper']) < 1e-3, f"ci_upper is incorrect. Expected approx {truth['ci_upper']}, got {results['ci_upper']}"
    assert abs(results['posterior_mean'] - truth['posterior_mean']) < 1e-3, f"posterior_mean is incorrect. Expected approx {truth['posterior_mean']}, got {results['posterior_mean']}"
    assert results['most_similar_user_id'] == truth['most_similar_user_id'], f"most_similar_user_id is incorrect. Expected {truth['most_similar_user_id']}, got {results['most_similar_user_id']}"


def test_bootstrap_plot_exists_and_valid(monkeypatch):
    import matplotlib.pyplot as plt
    from matplotlib.axes import Axes
    from matplotlib.image import imread

    script_path = '/home/user/plot.py'
    plot_path = '/home/user/bootstrap_plot.png'
    assert os.path.exists(script_path), f'The file {script_path} is missing.'
    assert os.path.isfile(script_path), f'{script_path} is not a file.'

    _, expected_distribution = calculate_truth()
    captured_histograms = []
    original_hist = Axes.hist

    def recording_hist(self, x, *args, **kwargs):
        try:
            captured_histograms.append(np.asarray(x, dtype=float).ravel().copy())
        except (TypeError, ValueError):
            pass
        return original_hist(self, x, *args, **kwargs)

    monkeypatch.setattr(Axes, 'hist', recording_hist)
    if os.path.exists(plot_path):
        os.remove(plot_path)
    plt.close('all')

    old_cwd = os.getcwd()
    try:
        os.chdir('/home/user')
        runpy.run_path(script_path, run_name='__main__')
    finally:
        os.chdir(old_cwd)

    assert os.path.exists(plot_path), f'The file {plot_path} is missing. Did you fix and run plot.py?'
    assert os.path.isfile(plot_path), f'{plot_path} is not a file.'

    size = os.path.getsize(plot_path)
    assert size > 1000, f'The file {plot_path} is too small ({size} bytes). It might be a blank image or corrupted.'

    with open(plot_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'bootstrap_plot.png is not a valid PNG file.'
    pixels = np.asarray(imread(plot_path))
    assert pixels.ndim in (2, 3) and pixels.shape[0] >= 100 and pixels.shape[1] >= 100, 'Plot image has invalid dimensions.'
    rgb = pixels[..., :3] if pixels.ndim == 3 else pixels
    assert float(np.ptp(rgb)) > 0.05 and float(np.std(rgb)) > 0.01, 'The saved plot appears blank.'

    matching_histogram = any(
        values.size == expected_distribution.size
        and np.allclose(np.sort(values), np.sort(expected_distribution), rtol=0, atol=1e-10)
        for values in captured_histograms
    )
    assert matching_histogram, 'plot.py did not plot the requested 1000-iteration bootstrap distribution.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
