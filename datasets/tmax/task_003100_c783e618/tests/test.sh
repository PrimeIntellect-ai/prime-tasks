#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from pydantic import BaseModel, ValidationError
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV

SCRIPT_PATH = '/home/user/pipeline.py'
DATA_PATH = '/home/user/products.csv'
RESULTS_PATH = '/home/user/model_results.json'


class Product(BaseModel):
    product_id: int
    text: str
    label: str


def validate_record(record):
    if hasattr(Product, 'model_validate'):
        return Product.model_validate(record)
    return Product.parse_obj(record)


def record_dict(model):
    if hasattr(model, 'model_dump'):
        return model.model_dump()
    return model.dict()


def expected_results(csv_path):
    df = pd.read_csv(csv_path)
    valid = []
    for record in df.to_dict(orient='records'):
        try:
            valid.append(record_dict(validate_record(record)))
        except (ValidationError, TypeError, ValueError):
            pass

    clean = pd.DataFrame(valid)
    features = TfidfVectorizer(max_features=500, stop_words='english').fit_transform(clean['text'])
    reduced = TruncatedSVD(n_components=20, random_state=42).fit_transform(features)
    search = GridSearchCV(
        LogisticRegression(random_state=42),
        {'C': [0.1, 1.0, 10.0]},
        cv=3,
    )
    search.fit(reduced, clean['label'])
    return float(search.best_params_['C']), float(search.best_score_)


def run_and_read():
    if os.path.lexists(RESULTS_PATH):
        if os.path.isdir(RESULTS_PATH) and not os.path.islink(RESULTS_PATH):
            pytest.fail(f'{RESULTS_PATH} is a directory')
        os.unlink(RESULTS_PATH)

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=180,
        env={**os.environ, 'PYTHONHASHSEED': '0'},
    )
    assert completed.returncode == 0, (
        f'pipeline.py failed with exit code {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    assert os.path.isfile(RESULTS_PATH), 'Running pipeline.py did not generate model_results.json.'
    try:
        with open(RESULTS_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'{RESULTS_PATH} does not contain valid JSON: {exc}')


def assert_matches_expected(results, expected_c, expected_score):
    assert 'best_C' in results, "Key 'best_C' is missing from model_results.json."
    assert 'best_score' in results, "Key 'best_score' is missing from model_results.json."
    assert isinstance(results['best_C'], (int, float)) and not isinstance(results['best_C'], bool)
    assert isinstance(results['best_score'], (int, float)) and not isinstance(results['best_score'], bool)
    assert float(results['best_C']) == expected_c, (
        f"best_C was {results['best_C']}, but GridSearchCV computed {expected_c}."
    )
    assert float(results['best_score']) == pytest.approx(expected_score, abs=1e-12), (
        f"best_score was {results['best_score']}, but GridSearchCV computed {expected_score}."
    )


def make_hidden_dataset():
    rng = np.random.RandomState(7319)
    labels = ['alpha', 'beta', 'gamma']
    category_words = {
        'alpha': ['amber', 'anchor', 'apple', 'arrow', 'atlas', 'avenue', 'acorn', 'apron'],
        'beta': ['beacon', 'birch', 'blade', 'bloom', 'brick', 'brook', 'button', 'bundle'],
        'gamma': ['cabin', 'cactus', 'candle', 'cedar', 'circle', 'cloud', 'copper', 'crystal'],
    }
    shared = ['quality', 'item', 'modern', 'useful', 'daily', 'simple', 'value', 'design']
    rows = []
    for i in range(240):
        source = labels[i % 3]
        words = list(rng.choice(category_words[source], 7, replace=True))
        other = labels[(labels.index(source) + int(rng.randint(1, 3))) % 3]
        words += list(rng.choice(category_words[other], 2, replace=True))
        words += list(rng.choice(shared, 3, replace=True))
        rng.shuffle(words)
        label = source
        if rng.rand() < 0.14:
            label = labels[(labels.index(source) + int(rng.randint(1, 3))) % 3]
        rows.append({'product_id': i, 'text': ' '.join(words), 'label': label})

    # These rows must be rejected by integer schema validation. If retained, their
    # contradictory examples materially change the fitted model and CV result.
    for i in range(60):
        source = labels[i % 3]
        wrong = labels[(i + 1) % 3]
        words = list(rng.choice(category_words[source], 10, replace=True)) + list(rng.choice(shared, 2))
        rows.append({'product_id': f'invalid-{i}', 'text': ' '.join(words), 'label': wrong})
    rows.append({'product_id': 9999, 'text': None, 'label': 'alpha'})
    return pd.DataFrame(rows)


def test_pipeline_executes_and_computes_results():
    assert os.path.exists(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    try:
        make_hidden_dataset().to_csv(DATA_PATH, index=False)
        expected_c, expected_score = expected_results(DATA_PATH)
        assert_matches_expected(run_and_read(), expected_c, expected_score)
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)

    # Re-run on the task's original input, both restoring the requested final
    # artifact and verifying its independently computed values.
    expected_c, expected_score = expected_results(DATA_PATH)
    assert_matches_expected(run_and_read(), expected_c, expected_score)


def test_pipeline_script_exists():
    """Verify that the pipeline.py script exists."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist. The task requires writing this script."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_model_results_json():
    """Verify that model_results.json exists and contains the correct structure and plausible values."""
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist. Did the script run successfully?"
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."

    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} does not contain valid JSON.")

    assert "best_C" in results, "Key 'best_C' is missing from model_results.json."
    assert "best_score" in results, "Key 'best_score' is missing from model_results.json."

    best_c = results["best_C"]
    best_score = results["best_score"]

    assert isinstance(best_c, (int, float)), f"'best_C' must be a number, got {type(best_c).__name__}."
    assert best_c in [0.1, 1.0, 10.0], f"'best_C' must be one of the grid values [0.1, 1.0, 10.0], got {best_c}."

    assert isinstance(best_score, (int, float)), f"'best_score' must be a number, got {type(best_score).__name__}."
    assert 0.0 <= best_score <= 1.0, f"'best_score' must be between 0.0 and 1.0, got {best_score}."

    # Given the clear separation of clusters based on the synthetic words, the model should achieve very high accuracy
    assert best_score > 0.8, f"'best_score' should be high (> 0.8) given the dataset separation, but got {best_score}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
