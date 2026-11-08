#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import stat
import subprocess

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.model_selection import train_test_split

SCRIPT = '/home/user/recommend.py'
DATA = '/home/user/data/articles.csv'
METRICS = '/home/user/metrics.json'
RECS = '/home/user/recommendations.csv'
QUERY = 'Deep learning and neural networks'


def expected_results(data_path):
    df = pd.read_csv(data_path)
    df['id'] = pd.to_numeric(df['id'], errors='coerce')
    df = df.dropna(subset=['id', 'title', 'text']).copy()
    df['id'] = df['id'].astype(int)

    train_df, test_df = train_test_split(
        df, test_size=0.25, random_state=42
    )

    vectorizer = TfidfVectorizer()
    vectorizer.fit(train_df['text'])
    train_x = vectorizer.transform(train_df['text'])
    test_x = vectorizer.transform(test_df['text'])

    metrics = {
        'train_avg_sim': float(cosine_similarity(train_x).mean()),
        'test_avg_sim': float(cosine_similarity(test_x).mean()),
    }

    query_x = vectorizer.transform([QUERY])
    similarities = cosine_similarity(query_x, train_x).ravel()
    top = np.argsort(-similarities, kind='stable')[:2]
    recs = [
        {
            'id': int(train_df.iloc[i]['id']),
            'title': str(train_df.iloc[i]['title']),
            'similarity': float(similarities[i]),
        }
        for i in top
    ]
    return metrics, recs


def run_script():
    for path in (METRICS, RECS):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'recommend.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def check_outputs(expected_metrics, expected_recs):
    # Preserve and strengthen the original metrics assertions.
    assert os.path.isfile(METRICS), f'{METRICS} does not exist.'
    with open(METRICS, 'r', encoding='utf-8') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f'{METRICS} is not a valid JSON file.') from exc

    assert 'train_avg_sim' in metrics, "metrics.json is missing the 'train_avg_sim' key."
    assert 'test_avg_sim' in metrics, "metrics.json is missing the 'test_avg_sim' key."
    assert set(metrics) == {'train_avg_sim', 'test_avg_sim'}, 'metrics.json must contain exactly the required keys.'

    for key in ('train_avg_sim', 'test_avg_sim'):
        assert isinstance(metrics[key], (int, float)) and not isinstance(metrics[key], bool), f"'{key}' must be a number."
        assert math.isfinite(metrics[key]), f"'{key}' must be finite."
        assert math.isclose(
            float(metrics[key]), expected_metrics[key], rel_tol=1e-9, abs_tol=1e-10
        ), f"Incorrect {key}: expected {expected_metrics[key]}, got {metrics[key]}."

    # Preserve and strengthen the original recommendation assertions.
    assert os.path.isfile(RECS), f'{RECS} does not exist.'
    with open(RECS, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'title', 'similarity'], 'CSV columns must be exactly: id, title, similarity'
        rows = list(reader)

    assert len(rows) == 2, f'Expected exactly 2 recommendations, but found {len(rows)}.'
    assert all(len(row) == 3 for row in rows), 'Every recommendation row must contain exactly three fields.'

    parsed = []
    for row in rows:
        try:
            rec_id = int(row[0])
            similarity = float(row[2])
        except ValueError as exc:
            raise AssertionError("CSV contains invalid data types for 'id' or 'similarity'.") from exc
        assert math.isfinite(similarity), 'Recommendation similarities must be finite.'
        parsed.append((rec_id, row[1], similarity))

    assert parsed[0][2] >= parsed[1][2], 'Recommendations must be sorted by similarity in descending order.'

    for actual, expected in zip(parsed, expected_recs):
        assert actual[0] == expected['id'], f"Incorrect recommendation id: expected {expected['id']}, got {actual[0]}."
        assert actual[1] == expected['title'], f"Incorrect title for recommendation id {expected['id']}."
        assert math.isclose(
            actual[2], expected['similarity'], rel_tol=1e-9, abs_tol=1e-10
        ), f"Incorrect similarity for recommendation id {expected['id']}."


def test_pipeline_behavior_and_final_outputs():
    assert os.path.exists(SCRIPT), f'{SCRIPT} does not exist.'
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} must be a regular file.'
    assert os.path.getsize(SCRIPT) > 0, f'{SCRIPT} is empty.'

    with open(DATA, 'rb') as f:
        original_data = f.read()

    challenge = b'''id,title,text\n101,Vision AI,Deep neural networks for vision vision tasks.\n102,Applied ML,Neural networks and learning applications.\nbad,Broken ID,This malformed identifier must be removed.\n103,Learning Systems,Deep learning systems use neural models.\n104,Kitchen,Cooking recipes and kitchen baking.\n105,Statistics,Statistics probability and data analysis.\n106,Astronomy,Astronomy stars galaxy telescope.\n107,Security,Network security protocols and encryption.\n108,Gardening,Gardening soil plants and outdoor care.\n109,No Text,\n110,,A row with a missing title.\n'''

    try:
        with open(DATA, 'wb') as f:
            f.write(challenge)
        expected_metrics, expected_recs = expected_results(DATA)
        run_script()
        check_outputs(expected_metrics, expected_recs)
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)

    # Leave the requested artifacts generated from the real supplied dataset.
    expected_metrics, expected_recs = expected_results(DATA)
    run_script()
    check_outputs(expected_metrics, expected_recs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
