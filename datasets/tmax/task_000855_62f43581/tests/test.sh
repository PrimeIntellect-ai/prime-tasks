#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import os
import runpy
import secrets
import subprocess
import sys

import numpy as np
import scipy.stats
import matplotlib.pyplot as plt
import matplotlib.image as mpimg

SCRIPT = '/home/user/analyze.py'
CSV_PATH = '/home/user/ab_test_data.csv'
PROB_PATH = '/home/user/prob_B_better.txt'
PLOT_PATH = '/home/user/posterior_plot.png'

assert os.path.isfile(SCRIPT), f'Missing script: {SCRIPT}'
assert os.path.isfile(CSV_PATH), f'Missing data: {CSV_PATH}'

with open(CSV_PATH, 'rb') as f:
    original_csv = f.read()

# Use an unpredictable second dataset to verify that the script really aggregates
# the CSV rather than retaining constants tailored to the supplied dataset.
trials_a = 880 + secrets.randbelow(31)
trials_b = 930 + secrets.randbelow(31)
successes_a = 78 + secrets.randbelow(12)
successes_b = 122 + secrets.randbelow(12)

try:
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['user_id', 'variant', 'converted'])
        uid = 0
        for variant, trials, successes in (
            ('A', trials_a, successes_a),
            ('B', trials_b, successes_b),
        ):
            # Interleave successes and failures so aggregation cannot rely on a block
            # of leading converted rows.
            values = [1] * successes + [0] * (trials - successes)
            rng = np.random.RandomState(1000 + trials + successes)
            rng.shuffle(values)
            for converted in values:
                writer.writerow([f'challenge_{uid}', variant, int(converted)])
                uid += 1

    for path in (PROB_PATH, PLOT_PATH):
        if os.path.exists(path):
            os.remove(path)

    events = []
    draws = []
    plotted = []

    original_seed = np.random.seed
    original_np_beta = np.random.beta
    original_scipy_rvs = scipy.stats.beta.rvs
    original_plot = plt.plot

    def checked_seed(value=None, *args, **kwargs):
        events.append(('seed', value))
        return original_seed(value, *args, **kwargs)

    def checked_np_beta(a, b, *args, **kwargs):
        size = kwargs.get('size', args[0] if args else None)
        events.append(('draw', 'numpy'))
        draws.append(('numpy', float(a), float(b), size))
        return original_np_beta(a, b, *args, **kwargs)

    def checked_scipy_rvs(*args, **kwargs):
        # scipy.stats.beta.rvs(a, b, loc=0, scale=1, size=...)
        a = kwargs.get('a', args[0] if len(args) > 0 else None)
        b = kwargs.get('b', args[1] if len(args) > 1 else None)
        size = kwargs.get('size', args[4] if len(args) > 4 else None)
        events.append(('draw', 'scipy'))
        draws.append(('scipy', float(a), float(b), size))
        return original_scipy_rvs(*args, **kwargs)

    def checked_plot(*args, **kwargs):
        if len(args) >= 2:
            plotted.append((np.asarray(args[0]), np.asarray(args[1]), kwargs.get('label')))
        return original_plot(*args, **kwargs)

    np.random.seed = checked_seed
    np.random.beta = checked_np_beta
    scipy.stats.beta.rvs = checked_scipy_rvs
    plt.plot = checked_plot
    try:
        runpy.run_path(SCRIPT, run_name='__main__')
    finally:
        np.random.seed = original_seed
        np.random.beta = original_np_beta
        scipy.stats.beta.rvs = original_scipy_rvs
        plt.plot = original_plot
        plt.close('all')

    assert os.path.isfile(PROB_PATH), f'Missing file after executing script: {PROB_PATH}'
    assert os.path.isfile(PLOT_PATH), f'Missing file after executing script: {PLOT_PATH}'

    alpha_a, beta_a = 1 + successes_a, 1 + trials_a - successes_a
    alpha_b, beta_b = 1 + successes_b, 1 + trials_b - successes_b

    def sample_count(size):
        if size is None:
            return 1
        return int(np.prod(size)) if isinstance(size, (tuple, list)) else int(size)

    counts = {'A': 0, 'B': 0}
    for _, a, b, size in draws:
        if np.isclose(a, alpha_a) and np.isclose(b, beta_a):
            counts['A'] += sample_count(size)
        elif np.isclose(a, alpha_b) and np.isclose(b, beta_b):
            counts['B'] += sample_count(size)
        else:
            raise AssertionError(f'Beta samples used incorrect posterior parameters: ({a}, {b})')

    assert counts['A'] == 1_000_000, f'Variant A must use exactly 1,000,000 posterior samples, got {counts["A"]}'
    assert counts['B'] == 1_000_000, f'Variant B must use exactly 1,000,000 posterior samples, got {counts["B"]}'

    first_draw = next((i for i, event in enumerate(events) if event[0] == 'draw'), None)
    assert first_draw is not None, 'No Beta posterior sampling was observed'
    assert first_draw > 0 and events[first_draw - 1] == ('seed', 42), \
        'np.random.seed(42) must be called immediately before posterior sampling'

    expected_rng = np.random.RandomState(42)
    expected_a = expected_rng.beta(alpha_a, beta_a, 1_000_000)
    expected_b = expected_rng.beta(alpha_b, beta_b, 1_000_000)
    expected_probability = f'{np.mean(expected_b > expected_a):.4f}'
    with open(PROB_PATH) as f:
        challenge_content = f.read().strip()
    assert challenge_content == expected_probability, \
        f'Expected challenge probability {expected_probability}, found {challenge_content!r}'

    # Confirm that both plotted curves are the posteriors derived from the data.
    matched = {'A': False, 'B': False}
    for x, y, label in plotted:
        if x.ndim != 1 or y.shape != x.shape or x.size < 50:
            continue
        if np.allclose(y, scipy.stats.beta.pdf(x, alpha_a, beta_a), rtol=1e-6, atol=1e-8):
            matched['A'] = True
        if np.allclose(y, scipy.stats.beta.pdf(x, alpha_b, beta_b), rtol=1e-6, atol=1e-8):
            matched['B'] = True
    assert matched['A'] and matched['B'], 'The plot must contain both data-derived posterior density curves'
finally:
    with open(CSV_PATH, 'wb') as f:
        f.write(original_csv)

# Execute the finished artifact against the supplied data and retain the original
# verifier's exact output assertions.
for path in (PROB_PATH, PLOT_PATH):
    if os.path.exists(path):
        os.remove(path)
subprocess.run([sys.executable, SCRIPT], cwd='/home/user', check=True, timeout=180)

assert os.path.isfile(PROB_PATH), f'Missing file: {PROB_PATH}'
with open(PROB_PATH) as f:
    content = f.read().strip()
assert content == '0.9839', f"Expected probability '0.9839', but found '{content}' in {PROB_PATH}"

assert os.path.isfile(PLOT_PATH), f'Missing file: {PLOT_PATH}'
file_size = os.path.getsize(PLOT_PATH)
assert file_size > 5000, f'Plot file {PLOT_PATH} is too small ({file_size} bytes), likely blank.'
with open(PLOT_PATH, 'rb') as f:
    assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'posterior_plot.png is not a valid PNG file'
image = np.asarray(mpimg.imread(PLOT_PATH), dtype=float)
assert image.ndim in (2, 3) and image.size > 0, 'Plot image could not be decoded'
assert np.isfinite(image).all(), 'Plot image contains invalid pixel values'
assert float(np.max(image) - np.min(image)) > 0.1 and float(np.std(image)) > 0.01, \
    'Plot image is blank or effectively uniform'
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
