#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

EXPERIMENT = '/home/user/experiment.py'
DATA = '/home/user/data.csv'
SCORE = '/home/user/best_score.txt'
PLOT = '/home/user/results.png'


def expected_score(df):
    grid = GridSearchCV(
        Ridge(),
        {'alpha': [0.1, 1.0, 10.0]},
        cv=5,
        scoring='neg_mean_squared_error',
    )
    grid.fit(df[['x1', 'x2']], df['y'].astype(float))
    return f"{-grid.best_score_:.4f}"


def run_experiment():
    for path in (SCORE, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        ['python3', EXPERIMENT],
        cwd='/home/user',
        check=True,
        timeout=120,
    )


def validate_artifacts(expected):
    assert os.path.isfile(SCORE), f"The file {SCORE} does not exist. Did you run the script?"
    with open(SCORE, 'r') as f:
        content = f.read().strip()
    assert content == expected, (
        f"Expected score '{expected}' in {SCORE}, but found '{content}'. "
        "Did you fix the schema enforcement bug so that 'y' is treated as a float?"
    )

    assert os.path.isfile(PLOT), f"The file {PLOT} does not exist. Did you run the script?"
    file_size = os.path.getsize(PLOT)
    assert file_size > 5000, (
        f"The file {PLOT} is too small ({file_size} bytes). "
        "It appears to be a blank or cleared plot. Did you fix the matplotlib bug?"
    )
    with open(PLOT, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"{PLOT} is not a PNG file"

    image = np.asarray(mpimg.imread(PLOT))
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    rgb = image[..., :3] if image.ndim == 3 else image
    assert np.isfinite(rgb).all(), "The plot contains invalid pixel values"
    background = rgb[0, 0]
    if rgb.ndim == 3:
        changed = np.any(np.abs(rgb - background) > 0.02, axis=2)
    else:
        changed = np.abs(rgb - background) > 0.02
    assert np.count_nonzero(changed) > 1000 and float(np.ptp(rgb)) > 0.1, (
        "results.png is a valid image but appears blank"
    )
    return image.copy()


def test_experiment_executes_and_generates_correct_artifacts():
    assert os.path.isfile(EXPERIMENT), f"The required script {EXPERIMENT} does not exist"

    with open(DATA, 'rb') as f:
        original_data = f.read()

    rng = np.random.default_rng(73129)
    x1 = rng.uniform(-1.5, 2.0, 85)
    x2 = rng.uniform(-0.7, 1.8, 85)
    y = 2.35 * x1 - 1.42 * x2 + 0.37 + rng.normal(0, 0.31, 85)
    challenge = pd.DataFrame({'x1': x1, 'x2': x2, 'y': y})
    challenge_expected = expected_score(challenge)

    try:
        challenge.to_csv(DATA, index=False)
        run_experiment()
        challenge_image = validate_artifacts(challenge_expected)
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)

    original_df = pd.read_csv(DATA)
    run_experiment()
    original_image = validate_artifacts(expected_score(original_df))

    # Preserve the original verifier's exact expected-value assertion.
    with open(SCORE, 'r') as f:
        content = f.read().strip()
    assert content == "0.2974", (
        f"Expected score '0.2974' in {SCORE}, but found '{content}'. "
        "Did you fix the schema enforcement bug so that 'y' is treated as a float?"
    )

    # A fixed arbitrary image is not an experiment-results plot.
    same_pixels = (
        challenge_image.shape == original_image.shape
        and np.array_equal(challenge_image, original_image)
    )
    assert not same_pixels, "results.png did not change when the experiment data changed"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
