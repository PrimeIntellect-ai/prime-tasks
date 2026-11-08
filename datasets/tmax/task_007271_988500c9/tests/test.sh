#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import subprocess
import sys

import pytest

HOME = '/home/user'
SCRIPT = os.path.join(HOME, 'train_model.py')
RAW = os.path.join(HOME, 'raw_data.csv')
CLEAN = os.path.join(HOME, 'clean_data.csv')
METRICS = os.path.join(HOME, 'metrics.json')


@pytest.fixture(scope='session', autouse=True)
def run_submitted_pipeline():
    assert os.path.isfile(SCRIPT), f'Training script is missing: {SCRIPT}'
    if os.path.exists(METRICS):
        os.remove(METRICS)

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'train_model.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(METRICS), (
        'Executing train_model.py did not create /home/user/metrics.json'
    )


def _target_name(assign):
    if len(assign.targets) == 1 and isinstance(assign.targets[0], ast.Name):
        return assign.targets[0].id
    return None


def _call_name(call):
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return None


def _literal_keyword(call, name):
    for keyword in call.keywords:
        if keyword.arg == name:
            return ast.literal_eval(keyword.value)
    raise AssertionError(f'Missing required keyword argument {name!r}')


def _constructor(tree, class_name):
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
            if _call_name(node.value) == class_name:
                target = _target_name(node)
                if target:
                    return target, node.value, node.lineno
    raise AssertionError(f'Could not find construction of {class_name}')


def _assigned_method_call(tree, owner, method, input_name):
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        target = _target_name(node)
        if not target:
            continue
        for child in ast.walk(node.value):
            if not isinstance(child, ast.Call) or not isinstance(child.func, ast.Attribute):
                continue
            if not isinstance(child.func.value, ast.Name):
                continue
            if child.func.value.id != owner or child.func.attr != method:
                continue
            if child.args and isinstance(child.args[0], ast.Name) and child.args[0].id == input_name:
                return target, child.lineno
    raise AssertionError(f'Could not find {owner}.{method}({input_name}) assigned to a variable')


def test_clean_data_file():
    assert os.path.isfile(CLEAN), f'Cleaned data file is missing: {CLEAN}'
    assert os.path.isfile(RAW), f'Raw data file is missing: {RAW}'

    with open(RAW, 'r', newline='', encoding='utf-8') as f:
        raw_rows = list(csv.reader(f))
    with open(CLEAN, 'r', newline='', encoding='utf-8') as f:
        clean_rows = list(csv.reader(f))

    assert raw_rows, f'File {RAW} is empty.'
    assert clean_rows, f'File {CLEAN} is empty.'
    assert raw_rows[0] == ['text', 'label'], f'Unexpected raw-data header: {raw_rows[0]}'
    assert clean_rows[0] == ['text', 'label'], f"Expected header ['text', 'label'], got {clean_rows[0]}"
    assert len(raw_rows) - 1 == 300, f'Expected 300 rows in raw_data.csv, found {len(raw_rows) - 1}'
    assert len(clean_rows) - 1 == 300, f'Expected 300 rows of data, found {len(clean_rows) - 1} in {CLEAN}'

    for row_count, (raw_row, clean_row) in enumerate(zip(raw_rows[1:], clean_rows[1:]), 1):
        assert len(raw_row) == 2, f'Raw row {row_count} does not have exactly 2 columns.'
        assert len(clean_row) == 2, f'Row {row_count} does not have exactly 2 columns.'
        text = clean_row[0]
        assert '!' not in text, f"Punctuation '!' found in clean_data.csv at row {row_count}"
        assert '?' not in text, f"Punctuation '?' found in clean_data.csv at row {row_count}"
        assert text == text.lower(), f'Uppercase letters found in clean_data.csv at row {row_count}'

        expected_text = raw_row[0].lower().replace('!', '').replace('?', '')
        assert clean_row[0] == expected_text, f'Cleaned text at row {row_count} does not match raw_data.csv'
        assert clean_row[1] == raw_row[1], f'Label at row {row_count} does not match raw_data.csv'


def test_training_code_splits_before_fitting_transformers():
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=SCRIPT)

    split_assign = None
    split_call = None
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
            if _call_name(node.value) == 'train_test_split':
                split_assign, split_call = node, node.value
                break
    assert split_assign is not None, 'train_model.py must call train_test_split'
    assert len(split_assign.targets) == 1 and isinstance(split_assign.targets[0], (ast.Tuple, ast.List)), (
        'The train/test split results must be assigned to four variables'
    )
    split_names = [item.id for item in split_assign.targets[0].elts if isinstance(item, ast.Name)]
    assert len(split_names) == 4, 'The train/test split must produce X_train, X_test, y_train, and y_test values'
    x_train, x_test, y_train, y_test = split_names
    assert _literal_keyword(split_call, 'test_size') == 0.3
    assert _literal_keyword(split_call, 'random_state') == 42

    vectorizer, vectorizer_call, _ = _constructor(tree, 'TfidfVectorizer')
    assert _literal_keyword(vectorizer_call, 'max_features') == 50
    train_tfidf, vector_fit_line = _assigned_method_call(tree, vectorizer, 'fit_transform', x_train)
    test_tfidf, _ = _assigned_method_call(tree, vectorizer, 'transform', x_test)
    assert vector_fit_line > split_assign.lineno, 'TfidfVectorizer is fitted before train_test_split'

    vector_fit_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name) and node.func.value.id == vectorizer:
                if node.func.attr in ('fit', 'fit_transform'):
                    vector_fit_calls.append(node)
    assert len(vector_fit_calls) == 1, 'TfidfVectorizer must be fitted exactly once, only on training data'

    pca, pca_call, _ = _constructor(tree, 'PCA')
    assert _literal_keyword(pca_call, 'n_components') == 10
    assert _literal_keyword(pca_call, 'random_state') == 42
    train_pca, pca_fit_line = _assigned_method_call(tree, pca, 'fit_transform', train_tfidf)
    test_pca, _ = _assigned_method_call(tree, pca, 'transform', test_tfidf)
    assert pca_fit_line > split_assign.lineno, 'PCA is fitted before train_test_split'

    pca_fit_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name) and node.func.value.id == pca:
                if node.func.attr in ('fit', 'fit_transform'):
                    pca_fit_calls.append(node)
    assert len(pca_fit_calls) == 1, 'PCA must be fitted exactly once, only on training data'

    classifier, classifier_call, _ = _constructor(tree, 'LogisticRegression')
    assert _literal_keyword(classifier_call, 'random_state') == 42

    fit_ok = predict_ok = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if not isinstance(node.func.value, ast.Name) or node.func.value.id != classifier:
            continue
        arg_names = [arg.id if isinstance(arg, ast.Name) else None for arg in node.args]
        if node.func.attr == 'fit' and arg_names[:2] == [train_pca, y_train]:
            fit_ok = True
        if node.func.attr == 'predict' and arg_names[:1] == [test_pca]:
            predict_ok = True
    assert fit_ok, 'LogisticRegression must be fitted on the transformed training data and training labels'
    assert predict_ok, 'LogisticRegression must predict using the transformed test data'


def test_metrics_json():
    assert os.path.isfile(METRICS), f'Metrics file is missing: {METRICS}'

    with open(METRICS, 'r', encoding='utf-8') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {METRICS} does not contain valid JSON.')

    assert isinstance(metrics, dict), f'{METRICS} must contain a JSON object'
    assert set(metrics) == {'accuracy'}, f'{METRICS} must contain exactly the key accuracy'
    acc = metrics['accuracy']
    assert isinstance(acc, float), f'Accuracy must be a float, got {type(acc).__name__}'

    expected_acc = 0.9555555555555556
    assert abs(acc - expected_acc) < 1e-5, (
        f'Expected accuracy ~{expected_acc}, but got {acc}. The data leakage might not be correctly fixed, '
        'or hyperparameters were changed.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
