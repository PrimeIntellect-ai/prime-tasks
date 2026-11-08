#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
import sys

import pandas as pd
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

CLEANED = '/home/user/data/cleaned_data.csv'
PREDICTION = '/home/user/data/prediction.txt'


def test_cleaned_data_exists():
    assert os.path.isfile(CLEANED), "/home/user/data/cleaned_data.csv is missing. Did you run clean_pipeline.py?"


def test_cleaned_data_no_floats():
    with open(CLEANED, 'r') as f:
        content = f.read()

    assert ".0" not in content, "Found '.0' in cleaned_data.csv. The quality_label column was likely cast to float instead of Int64."

    lines = content.strip().split('\n')
    assert len(lines) >= 6, "cleaned_data.csv does not have the expected number of rows."
    assert lines[1].endswith(",1") or lines[1].endswith(",1\r"), "Row 101 should end with 1"
    assert lines[2].endswith(",0") or lines[2].endswith(",0\r"), "Row 102 should end with 0"
    assert lines[-1].endswith(",") or lines[-1].endswith(",\r"), "Row 105 should have an empty quality_label"


def test_predict_script_exists():
    assert os.path.isfile('/home/user/predict.py'), "/home/user/predict.py is missing. Did you write the prediction script?"


def test_prediction_output():
    assert os.path.isfile(PREDICTION), "/home/user/data/prediction.txt is missing. Did you save the prediction?"

    with open(PREDICTION, 'r') as f:
        pred = f.read().strip()

    assert pred == "0", f"Expected prediction to be '0', but got '{pred}'"


def test_pipeline_declares_nullable_integer_dtype():
    path = '/home/user/clean_pipeline.py'
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=path)
    constants = [node.value for node in ast.walk(tree) if isinstance(node, ast.Constant)]
    assert 'Int64' in constants, "clean_pipeline.py must explicitly use pandas nullable Int64 dtype"


def _run(cmd):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=60)


def test_scripts_execute_required_pipeline_on_unseen_data():
    paths = [
        '/home/user/data/notes.csv',
        '/home/user/data/metrics.csv',
        CLEANED,
        PREDICTION,
    ]
    backups = {}
    for path in paths:
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    try:
        token_zero = 'zero' + secrets.token_hex(10)
        token_one = 'one' + secrets.token_hex(10)
        common = 'common' + secrets.token_hex(10)
        label_for_zero = secrets.randbelow(2)
        label_for_one = 1 - label_for_zero

        notes_rows = []
        metrics_rows = []
        next_id = 7001
        for token, label in ((token_zero, label_for_zero), (token_one, label_for_one)):
            for i in range(4):
                notes_rows.append((next_id, f'{token} {token} {token} {common} specimen{i}'))
                metrics_rows.append((next_id, label))
                next_id += 1

        missing_rows = [
            (next_id, f'{token_zero} {token_zero} {common} unknownsample'),
            (next_id + 1, f'{token_one} {token_one} {common} unknownsample'),
        ]
        notes_rows.extend(missing_rows)

        notes_df = pd.DataFrame(notes_rows, columns=['id', 'text'])
        metrics_df = pd.DataFrame(list(reversed(metrics_rows)), columns=['id', 'quality_label'])
        notes_df.to_csv('/home/user/data/notes.csv', index=False)
        metrics_df.to_csv('/home/user/data/metrics.csv', index=False)

        clean_wrapper = r'''
import pandas as pd
import runpy
seen = []
original = pd.DataFrame.to_csv

def checked(self, path_or_buf=None, *args, **kwargs):
    if path_or_buf == '/home/user/data/cleaned_data.csv':
        assert 'quality_label' in self.columns
        assert str(self['quality_label'].dtype) == 'Int64', (
            'quality_label dtype at write time was %s, not Int64' % self['quality_label'].dtype
        )
        seen.append(True)
    return original(self, path_or_buf, *args, **kwargs)

pd.DataFrame.to_csv = checked
runpy.run_path('/home/user/clean_pipeline.py', run_name='__main__')
assert seen, 'clean_pipeline.py did not write cleaned_data.csv from an Int64 DataFrame'
'''
        result = _run([sys.executable, '-c', clean_wrapper])
        assert result.returncode == 0, "clean_pipeline.py failed or did not use Int64:\n" + result.stdout
        assert os.path.isfile(CLEANED), "clean_pipeline.py did not create cleaned_data.csv"

        with open(CLEANED, 'r', encoding='utf-8') as f:
            cleaned_text = f.read()
        assert '.0' not in cleaned_text, "Dynamic cleaned output contains float-form labels"

        cleaned = pd.read_csv(CLEANED)
        assert list(cleaned.columns) == ['id', 'text', 'quality_label']
        assert cleaned['id'].tolist() == notes_df['id'].tolist(), "The left join did not preserve note rows/order"
        assert cleaned['text'].tolist() == notes_df['text'].tolist()
        expected_labels = [dict(metrics_rows).get(i) for i in notes_df['id']]
        for actual, expected in zip(cleaned['quality_label'], expected_labels):
            if expected is None:
                assert pd.isna(actual)
            else:
                assert int(actual) == expected

        train = cleaned[cleaned['quality_label'].notna()]
        missing = cleaned[cleaned['quality_label'].isna()]
        reference_vectorizer = TfidfVectorizer()
        x_train = reference_vectorizer.fit_transform(train['text'])
        x_missing = reference_vectorizer.transform(missing['text'])
        reference_model = LogisticRegression(random_state=42)
        reference_model.fit(x_train, train['quality_label'].astype(int))
        expected_predictions = [int(x) for x in reference_model.predict(x_missing)]
        assert set(expected_predictions) == {0, 1}, "Internal challenge did not distinguish fixed predictions"

        predict_wrapper = r'''
import runpy
import sklearn.feature_extraction.text as text_module
import sklearn.linear_model as linear_module

RealVectorizer = text_module.TfidfVectorizer
RealModel = linear_module.LogisticRegression
events = []

class VectorizerProxy:
    def __init__(self, inner):
        self.inner = inner
    def fit(self, *args, **kwargs):
        events.append('vectorizer_fit')
        self.inner.fit(*args, **kwargs)
        return self
    def fit_transform(self, *args, **kwargs):
        events.append('vectorizer_fit_transform')
        return self.inner.fit_transform(*args, **kwargs)
    def transform(self, *args, **kwargs):
        events.append('vectorizer_transform')
        return self.inner.transform(*args, **kwargs)
    def __getattr__(self, name):
        return getattr(self.inner, name)

class ModelProxy:
    def __init__(self, inner):
        self.inner = inner
    def fit(self, *args, **kwargs):
        events.append('model_fit')
        self.inner.fit(*args, **kwargs)
        return self
    def predict(self, *args, **kwargs):
        events.append('model_predict')
        return self.inner.predict(*args, **kwargs)
    def __getattr__(self, name):
        return getattr(self.inner, name)

def vectorizer_factory(*args, **kwargs):
    assert args == () and kwargs == {}, 'TfidfVectorizer must use default parameters'
    events.append('vectorizer_init')
    return VectorizerProxy(RealVectorizer())

def model_factory(*args, **kwargs):
    assert args == (), 'LogisticRegression must not receive positional parameters'
    assert kwargs == {'random_state': 42}, (
        'LogisticRegression must use random_state=42 and otherwise default parameters'
    )
    events.append('model_init')
    return ModelProxy(RealModel(random_state=42))

text_module.TfidfVectorizer = vectorizer_factory
linear_module.LogisticRegression = model_factory
runpy.run_path('/home/user/predict.py', run_name='__main__')
assert 'vectorizer_init' in events
assert 'vectorizer_fit' in events or 'vectorizer_fit_transform' in events
assert 'vectorizer_transform' in events
assert 'model_init' in events
assert 'model_fit' in events
assert 'model_predict' in events
'''
        result = _run([sys.executable, '-c', predict_wrapper])
        assert result.returncode == 0, "predict.py failed or did not use the required sklearn pipeline:\n" + result.stdout
        assert os.path.isfile(PREDICTION), "predict.py did not create prediction.txt"

        with open(PREDICTION, 'r', encoding='utf-8') as f:
            lines = f.read().splitlines()
        assert lines == [str(x) for x in expected_predictions], (
            f"Expected predictions {expected_predictions}, but prediction.txt contained {lines}"
        )
        assert all(line in ('0', '1') for line in lines), "Predictions must be plain integers, one per line"
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
