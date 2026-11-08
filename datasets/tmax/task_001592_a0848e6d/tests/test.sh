#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import runpy
import secrets
import subprocess
import sys

os.environ['MPLBACKEND'] = 'Agg'

import matplotlib.pyplot as plt
import matplotlib.axes
import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from pandas.api.types import is_integer_dtype
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

USERS = '/home/user/data/users.csv'
PLOT = '/home/user/data/plot.png'
PARQUET = '/home/user/data/features.parquet'
RECOMMENDATIONS = '/home/user/recommendations.json'
VALIDATE = '/home/user/scripts/validate.py'
ETL = '/home/user/scripts/etl.py'
RECOMMEND = '/home/user/scripts/recommend.py'


def require_original_artifacts():
    assert os.path.isfile(PLOT), f'Plot file {PLOT} was not generated.'
    file_size = os.path.getsize(PLOT)
    assert file_size > 2000, f'Plot file {PLOT} is too small ({file_size} bytes), indicating it might still be blank.'

    assert os.path.isfile(PARQUET), f'Parquet file {PARQUET} was not generated.'
    with open(PARQUET, 'rb') as f:
        header = f.read(4)
        f.seek(-4, os.SEEK_END)
        footer = f.read(4)
    assert header == b'PAR1', f'{PARQUET} does not have a valid Parquet header.'
    assert footer == b'PAR1', f'{PARQUET} does not have a valid Parquet footer.'
    with open(PARQUET, 'rb') as f:
        content = f.read()
    assert b'id' in content, "Column 'id' not found in the Parquet file metadata."
    assert b'feature_vector' in content, "Column 'feature_vector' not found in the Parquet file metadata."

    assert os.path.isfile(RECOMMENDATIONS), f'Recommendations JSON file {RECOMMENDATIONS} was not generated.'
    with open(RECOMMENDATIONS) as f:
        data = json.load(f)
    expected = {'target': 101, 'similar': [103, 105]}
    assert data == expected, f'Recommendations JSON content is incorrect. Expected {expected}, got {data}.'


def run_validate(expected_ages):
    if os.path.exists(PLOT):
        os.remove(PLOT)
    plt.close('all')
    hist_values = []
    original_pyplot_hist = plt.hist
    original_axes_hist = matplotlib.axes.Axes.hist
    original_show = plt.show

    def record(values):
        try:
            hist_values.append(np.asarray(values, dtype=float).reshape(-1))
        except Exception:
            pass

    def pyplot_hist(values, *args, **kwargs):
        record(values)
        return original_pyplot_hist(values, *args, **kwargs)

    def axes_hist(self, values, *args, **kwargs):
        record(values)
        return original_axes_hist(self, values, *args, **kwargs)

    # Model backends where show() closes the displayed figure. A correct script
    # must save the populated figure before show(), or omit show() entirely.
    def closing_show(*args, **kwargs):
        plt.close('all')

    plt.hist = pyplot_hist
    matplotlib.axes.Axes.hist = axes_hist
    plt.show = closing_show
    try:
        runpy.run_path(VALIDATE, run_name='__main__')
    finally:
        plt.hist = original_pyplot_hist
        matplotlib.axes.Axes.hist = original_axes_hist
        plt.show = original_show
        plt.close('all')

    expected_ages = np.asarray(expected_ages, dtype=float)
    assert any(len(v) == len(expected_ages) and np.allclose(np.sort(v), np.sort(expected_ages))
               for v in hist_values), 'validate.py did not create a histogram from the CSV age column.'
    assert os.path.isfile(PLOT), 'validate.py did not save /home/user/data/plot.png.'
    assert os.path.getsize(PLOT) > 2000, 'The generated plot is too small to contain the requested histogram.'
    image = np.asarray(mpimg.imread(PLOT))
    assert image.ndim in (2, 3) and image.size > 0, 'plot.png is not a readable image.'
    visible = image[..., :3] if image.ndim == 3 else image
    assert float(np.std(visible)) > 0.01, 'plot.png has no visible plotted content.'
    pixels = visible.reshape(-1, visible.shape[-1]) if visible.ndim == 3 else visible.reshape(-1, 1)
    assert len(np.unique(pixels, axis=0)) > 20, 'plot.png appears blank rather than containing a histogram.'


def expected_features(users):
    tfidf = TfidfVectorizer().fit_transform(users['bio']).toarray()
    ages = users['age'].to_numpy(dtype=float).reshape(-1, 1) / 100.0
    return np.hstack([tfidf, ages])


def check_parquet(users):
    assert os.path.isfile(PARQUET), 'etl.py did not create features.parquet.'
    result = pd.read_parquet(PARQUET)
    assert list(result.columns) == ['id', 'feature_vector'], 'Parquet must contain exactly id and feature_vector columns.'
    assert len(result) == len(users), 'Parquet does not contain exactly one row per input user.'
    assert is_integer_dtype(result['id'].dtype), 'The id column must have an integer dtype.'
    assert set(map(int, result['id'])) == set(map(int, users['id'])), 'Parquet IDs do not match users.csv.'

    expected = expected_features(users)
    expected_by_id = {int(uid): expected[i] for i, uid in enumerate(users['id'])}
    for _, row in result.iterrows():
        vector = np.asarray(row['feature_vector'], dtype=float).reshape(-1)
        wanted = expected_by_id[int(row['id'])]
        assert vector.shape == wanted.shape, f'Feature vector for id {row["id"]} has the wrong length.'
        assert np.allclose(vector, wanted, rtol=1e-7, atol=1e-9), f'Feature vector for id {row["id"]} is incorrect.'
    return expected


def expected_recommendation(users, vectors):
    ids = users['id'].to_numpy(dtype=int)
    target_index = int(np.where(ids == 101)[0][0])
    scores = cosine_similarity(vectors[target_index:target_index + 1], vectors)[0]
    candidates = [i for i in range(len(ids)) if ids[i] != 101]
    candidates.sort(key=lambda i: -scores[i])
    return {'target': 101, 'similar': [int(ids[i]) for i in candidates[:2]]}


def run_pipeline_and_check(users, expected_json=None):
    run_validate(users['age'].to_numpy())

    if os.path.exists(PARQUET):
        os.remove(PARQUET)
    subprocess.run([sys.executable, ETL], check=True, timeout=60)
    vectors = check_parquet(users)

    if os.path.exists(RECOMMENDATIONS):
        os.remove(RECOMMENDATIONS)
    subprocess.run([sys.executable, RECOMMEND], check=True, timeout=60)
    assert os.path.isfile(RECOMMENDATIONS), 'recommend.py did not create recommendations.json.'
    with open(RECOMMENDATIONS) as f:
        actual = json.load(f)
    wanted = expected_json if expected_json is not None else expected_recommendation(users, vectors)
    assert actual == wanted, f'Incorrect recommendations: expected {wanted}, got {actual}.'


def main():
    for path in (VALIDATE, ETL, RECOMMEND):
        assert os.path.isfile(path), f'Required script {path} does not exist.'

    # Retain all original final-state assertions.
    require_original_artifacts()

    original_bytes = open(USERS, 'rb').read()
    try:
        original_users = pd.read_csv(USERS)
        run_pipeline_and_check(original_users, {'target': 101, 'similar': [103, 105]})

        # Exercise all scripts on an unpredictable second dataset, deriving every
        # expected vector and recommendation independently.
        token = secrets.token_hex(8)
        dynamic = pd.DataFrame([
            {'id': 101, 'name': 'Target', 'age': 34, 'bio': f'alpha{token} beta{token}'},
            {'id': 7001, 'name': 'Near', 'age': 33, 'bio': f'alpha{token} beta{token} extra{token}'},
            {'id': 8123, 'name': 'Partial', 'age': 22, 'bio': f'alpha{token} other{token}'},
            {'id': 9347, 'name': 'Far', 'age': 61, 'bio': f'unrelated{token} distinct{token}'},
            {'id': 4567, 'name': 'Other', 'age': 19, 'bio': f'separate{token} words{token}'},
        ])
        dynamic = dynamic.sample(frac=1, random_state=int.from_bytes(os.urandom(4), 'big')).reset_index(drop=True)
        dynamic.to_csv(USERS, index=False)
        run_pipeline_and_check(dynamic)
    finally:
        with open(USERS, 'wb') as f:
            f.write(original_bytes)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
