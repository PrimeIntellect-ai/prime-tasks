#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import euclidean_distances

RAW = Path('/home/user/raw_reviews.csv')
CLEAN = Path('/home/user/clean_reviews.csv')
PIPELINE = Path('/home/user/pipeline.py')
RESULT = Path('/home/user/representative_review.txt')
HEADER = ['ID', 'Date', 'Status', 'Review_Text']


def raw_verified_rows():
    with RAW.open('r', newline='') as f:
        reader = csv.reader(f)
        assert next(reader, None) == HEADER
        return [row for row in reader if len(row) >= 3 and row[2] == 'Verified']


def assert_clean_matches_raw():
    assert CLEAN.exists(), f'File {CLEAN} does not exist.'
    assert CLEAN.is_file(), f'Path {CLEAN} is not a file.'

    with CLEAN.open('r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f'File {CLEAN} is empty.'
        assert header == HEADER, f'Expected header {HEADER}, but got {header}.'

        actual = []
        for row_idx, row in enumerate(reader, start=2):
            assert len(row) == 4, f'Row {row_idx} does not have 4 columns.'
            assert row[2] == 'Verified', (
                f"Row {row_idx} has Status '{row[2]}' instead of 'Verified'."
            )
            actual.append(row)

    expected = raw_verified_rows()
    assert len(actual) == len(expected), (
        f'Expected {len(expected)} verified rows based on raw data, '
        f'but found {len(actual)} in {CLEAN}.'
    )
    assert actual == expected, (
        'clean_reviews.csv must contain the actual Verified rows from '
        'raw_reviews.csv, in their original order.'
    )


def expected_id(rows):
    frame = pd.DataFrame(rows, columns=HEADER)
    tfidf = TfidfVectorizer(stop_words='english', max_features=200)
    x_tfidf = tfidf.fit_transform(frame['Review_Text'])
    svd = TruncatedSVD(n_components=5, random_state=42)
    x_reduced = svd.fit_transform(x_tfidf)
    kmeans = KMeans(n_clusters=4, n_init=10, random_state=42)
    labels = kmeans.fit_predict(x_reduced)
    indices = np.where(labels == 0)[0]
    distances = euclidean_distances(
        x_reduced[indices], kmeans.cluster_centers_[0].reshape(1, -1)
    )
    selected = indices[np.argmin(distances)]
    return str(frame.iloc[selected]['ID'])


def write_clean(rows):
    with CLEAN.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(HEADER)
        writer.writerows(rows)


def run_instrumented_pipeline(tmp_path, expected_texts):
    expected_path = tmp_path / 'expected_texts.json'
    marker_path = tmp_path / 'pipeline_marker.txt'
    wrapper_path = tmp_path / 'run_pipeline.py'
    expected_path.write_text(json.dumps(expected_texts))

    wrapper_path.write_text(r'''import json
import os
import runpy

import pandas as pd
from sklearn.cluster import KMeans
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer

expected = json.load(open(os.environ['EXPECTED_TEXTS']))
seen = {'pandas': False, 'tfidf': False, 'svd': False, 'kmeans': False}
state = {}

orig_read_csv = pd.read_csv
orig_tf = TfidfVectorizer.fit_transform
orig_svd = TruncatedSVD.fit_transform
orig_fit = KMeans.fit
orig_predict = KMeans.fit_predict


def read_csv(self_or_path, *args, **kwargs):
    path = os.fspath(self_or_path)
    if os.path.abspath(path) == '/home/user/clean_reviews.csv':
        seen['pandas'] = True
    return orig_read_csv(self_or_path, *args, **kwargs)


def tf_fit_transform(self, raw_documents, *args, **kwargs):
    assert self.stop_words == 'english', 'TfidfVectorizer must use stop_words="english"'
    assert self.max_features == 200, 'TfidfVectorizer must use max_features=200'
    assert list(raw_documents) == expected, 'TF-IDF must consume the clean Review_Text values'
    output = orig_tf(self, raw_documents, *args, **kwargs)
    state['tfidf_output'] = output
    seen['tfidf'] = True
    return output


def svd_fit_transform(self, X, *args, **kwargs):
    assert self.n_components == 5, 'TruncatedSVD must use n_components=5'
    assert self.random_state == 42, 'TruncatedSVD must use random_state=42'
    assert X is state.get('tfidf_output'), 'SVD must consume the TF-IDF output'
    output = orig_svd(self, X, *args, **kwargs)
    state['svd_output'] = output
    seen['svd'] = True
    return output


def check_kmeans(self, X):
    assert self.n_clusters == 4, 'KMeans must use n_clusters=4'
    assert self.n_init == 10, 'KMeans must use n_init=10'
    assert self.random_state == 42, 'KMeans must use random_state=42'
    assert X is state.get('svd_output'), 'KMeans must consume the SVD output'
    seen['kmeans'] = True


def km_fit(self, X, *args, **kwargs):
    check_kmeans(self, X)
    return orig_fit(self, X, *args, **kwargs)


def km_fit_predict(self, X, *args, **kwargs):
    check_kmeans(self, X)
    return orig_predict(self, X, *args, **kwargs)


pd.read_csv = read_csv
TfidfVectorizer.fit_transform = tf_fit_transform
TruncatedSVD.fit_transform = svd_fit_transform
KMeans.fit = km_fit
KMeans.fit_predict = km_fit_predict

runpy.run_path('/home/user/pipeline.py', run_name='__main__')
assert all(seen.values()), 'pipeline must use pandas and all required sklearn stages'
open(os.environ['MARKER'], 'w').write('ok')
''')

    env = os.environ.copy()
    env['EXPECTED_TEXTS'] = str(expected_path)
    env['MARKER'] = str(marker_path)
    result = subprocess.run(
        [sys.executable, str(wrapper_path)], text=True, capture_output=True,
        timeout=60, env=env
    )
    assert result.returncode == 0, (
        f'pipeline.py failed or did not use the required processing stages.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert marker_path.read_text() == 'ok'


def assert_result(wanted):
    assert RESULT.exists(), f'File {RESULT} does not exist.'
    assert RESULT.is_file(), f'Path {RESULT} is not a file.'
    content = RESULT.read_text()
    assert re.fullmatch(r'[0-9]+\n?', content), (
        f'File {RESULT} must contain ONLY a single integer ID. Got: {content!r}'
    )
    assert content.strip() == wanted, (
        f'Expected representative ID {wanted}, but got {content.strip()}.'
    )


def test_complete_pipeline(tmp_path):
    assert RAW.is_file(), f'Raw input {RAW} is missing.'
    assert_clean_matches_raw()
    original_rows = raw_verified_rows()

    assert PIPELINE.exists(), f'File {PIPELINE} does not exist.'
    assert PIPELINE.is_file(), f'Path {PIPELINE} is not a file.'
    assert not PIPELINE.is_symlink(), f'Path {PIPELINE} must be a regular Python script.'

    original_clean = CLEAN.read_bytes()
    original_result = RESULT.read_bytes() if RESULT.is_file() else None

    try:
        # Exercise the submitted script on fresh, unpredictable variants so a
        # precomputed or hardcoded representative ID cannot pass.
        for round_number in range(2):
            rows = [row[:] for row in original_rows]
            random.SystemRandom().shuffle(rows)
            base = secrets.randbelow(700_000_000) + 100_000_000
            for index, row in enumerate(rows):
                row[0] = str(base + index)
                nonce = secrets.token_hex(8)
                row[3] = f'{row[3]} nonce{nonce}'
            write_clean(rows)
            if RESULT.exists():
                RESULT.unlink()
            round_dir = tmp_path / f'round_{round_number}'
            round_dir.mkdir()
            run_instrumented_pipeline(round_dir, [row[3] for row in rows])
            assert_result(expected_id(rows))
    finally:
        CLEAN.write_bytes(original_clean)
        if original_result is None:
            if RESULT.exists():
                RESULT.unlink()
        else:
            RESULT.write_bytes(original_result)

    # Execute the submitted pipeline on the required final input and verify its
    # final artifact against an independently derived answer.
    if RESULT.exists():
        RESULT.unlink()
    final_dir = tmp_path / 'final'
    final_dir.mkdir()
    run_instrumented_pipeline(final_dir, [row[3] for row in original_rows])
    assert_clean_matches_raw()
    assert_result(expected_id(original_rows))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
