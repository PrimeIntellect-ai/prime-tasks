#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import runpy

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

PIPELINE = '/home/user/etl_pipeline.py'
DATA = '/home/user/data.csv'
METRICS = '/home/user/metrics.json'


def matrix_equal(a, b):
    if hasattr(a, 'toarray'):
        a = a.toarray()
    if hasattr(b, 'toarray'):
        b = b.toarray()
    a = np.asarray(a)
    b = np.asarray(b)
    return a.shape == b.shape and np.allclose(a, b, rtol=1e-10, atol=1e-12)


def docs_equal(a, b):
    try:
        return list(a) == list(b)
    except Exception:
        return False


def test_pipeline_script_fixed_and_executable(monkeypatch):
    assert os.path.exists(PIPELINE), f'Missing file: {PIPELINE}'

    with open(PIPELINE, 'r') as f:
        content = f.read()

    # Preserve the original verifier's static assertions.
    assert 'train_test_split' in content, 'train_test_split is missing from the script'
    try:
        tree = ast.parse(content)
    except SyntaxError:
        assert False, f'Syntax error in {PIPELINE}'

    split_lineno = None
    tfidf_fit_lineno = None
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == 'train_test_split':
                split_lineno = node.lineno
            elif isinstance(node.func, ast.Attribute) and node.func.attr == 'fit_transform':
                if tfidf_fit_lineno is None:
                    tfidf_fit_lineno = node.lineno
    if split_lineno and tfidf_fit_lineno:
        assert split_lineno < tfidf_fit_lineno, \
            'train_test_split must be called before fit_transform to avoid data leakage'

    # Use a fresh, unpredictable dataset so precomputed metrics cannot pass.
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'big'))
    vocabulary = [f'word{i}' for i in range(80)]
    rows = []
    for i in range(180):
        label = int(rng.integers(0, 2))
        words = list(rng.choice(vocabulary, size=14, replace=True))
        correlated_label = label if rng.random() < 0.62 else 1 - label
        words.append('signal_zero' if correlated_label == 0 else 'signal_one')
        words.append(f'unique_{i}')
        rows.append({'text': ' '.join(words), 'label': label})
    challenge = pd.DataFrame(rows)

    # Independently derive the required result using the corrected pipeline.
    ref_X_train, ref_X_test, ref_y_train, ref_y_test = train_test_split(
        challenge['text'], challenge['label'], test_size=0.3, random_state=42
    )
    ref_vectorizer = TfidfVectorizer(max_features=100)
    ref_train_vec = ref_vectorizer.fit_transform(ref_X_train).toarray()
    ref_test_vec = ref_vectorizer.transform(ref_X_test).toarray()
    ref_pca = PCA(n_components=10, random_state=42)
    ref_train_pca = ref_pca.fit_transform(ref_train_vec)
    ref_test_pca = ref_pca.transform(ref_test_vec)
    ref_clf = LogisticRegression(random_state=42)
    ref_clf.fit(ref_train_pca, ref_y_train)
    expected_predictions = ref_clf.predict(ref_test_pca)
    expected_accuracy = float(accuracy_score(ref_y_test, expected_predictions))

    state = {
        'split': False,
        'train_docs': None,
        'test_docs': None,
        'train_y': None,
        'test_y': None,
        'vectorizer_fit_train': False,
        'vectorizer_train_transformed': False,
        'vectorizer_test_transformed': False,
        'vec_train': None,
        'vec_test': None,
        'pca_fit_train': False,
        'pca_train_transformed': False,
        'pca_test_transformed': False,
        'pca_train': None,
        'pca_test': None,
        'model_fit_train': False,
        'model_predict_test': False,
    }

    import sklearn.model_selection as model_selection
    import sklearn.feature_extraction.text as text_module
    import sklearn.decomposition as decomposition_module
    import sklearn.linear_model as linear_model_module

    original_split = model_selection.train_test_split
    original_tfidf_fit = text_module.TfidfVectorizer.fit
    original_tfidf_fit_transform = text_module.TfidfVectorizer.fit_transform
    original_tfidf_transform = text_module.TfidfVectorizer.transform
    original_pca_fit = decomposition_module.PCA.fit
    original_pca_fit_transform = decomposition_module.PCA.fit_transform
    original_pca_transform = decomposition_module.PCA.transform
    original_lr_fit = linear_model_module.LogisticRegression.fit
    original_lr_predict = linear_model_module.LogisticRegression.predict

    def checked_split(*arrays, **kwargs):
        assert kwargs.get('test_size') == 0.3, 'train_test_split must use test_size=0.3'
        assert kwargs.get('random_state') == 42, 'train_test_split must use random_state=42'
        result = original_split(*arrays, **kwargs)
        assert len(arrays) >= 2 and len(result) >= 4, 'Text and labels must be split together'
        state['split'] = True
        state['train_docs'], state['test_docs'] = result[0], result[1]
        state['train_y'], state['test_y'] = result[2], result[3]
        return result

    def checked_tfidf_fit(self, raw_documents, *args, **kwargs):
        assert state['split'], 'TF-IDF was fitted before the train/test split'
        assert docs_equal(raw_documents, state['train_docs']), 'TF-IDF must be fitted only on training text'
        state['vectorizer_fit_train'] = True
        return original_tfidf_fit(self, raw_documents, *args, **kwargs)

    def checked_tfidf_fit_transform(self, raw_documents, *args, **kwargs):
        assert state['split'], 'TF-IDF was fitted before the train/test split'
        assert docs_equal(raw_documents, state['train_docs']), 'TF-IDF must be fitted only on training text'
        state['vectorizer_fit_train'] = True
        result = original_tfidf_fit_transform(self, raw_documents, *args, **kwargs)
        state['vectorizer_train_transformed'] = True
        state['vec_train'] = result
        return result

    def checked_tfidf_transform(self, raw_documents, *args, **kwargs):
        result = original_tfidf_transform(self, raw_documents, *args, **kwargs)
        if docs_equal(raw_documents, state['train_docs']):
            state['vectorizer_train_transformed'] = True
            state['vec_train'] = result
        if docs_equal(raw_documents, state['test_docs']):
            state['vectorizer_test_transformed'] = True
            state['vec_test'] = result
        return result

    def checked_pca_fit(self, X, *args, **kwargs):
        assert state['vec_train'] is not None and matrix_equal(X, state['vec_train']), \
            'PCA must be fitted only on transformed training data'
        state['pca_fit_train'] = True
        return original_pca_fit(self, X, *args, **kwargs)

    def checked_pca_fit_transform(self, X, *args, **kwargs):
        assert state['vec_train'] is not None and matrix_equal(X, state['vec_train']), \
            'PCA must be fitted only on transformed training data'
        state['pca_fit_train'] = True
        result = original_pca_fit_transform(self, X, *args, **kwargs)
        state['pca_train_transformed'] = True
        state['pca_train'] = result
        return result

    def checked_pca_transform(self, X, *args, **kwargs):
        result = original_pca_transform(self, X, *args, **kwargs)
        if state['vec_train'] is not None and matrix_equal(X, state['vec_train']):
            state['pca_train_transformed'] = True
            state['pca_train'] = result
        if state['vec_test'] is not None and matrix_equal(X, state['vec_test']):
            state['pca_test_transformed'] = True
            state['pca_test'] = result
        return result

    def checked_lr_fit(self, X, y, *args, **kwargs):
        assert self.random_state == 42, 'LogisticRegression must use random_state=42'
        assert state['pca_train'] is not None and matrix_equal(X, state['pca_train']), \
            'LogisticRegression must be fitted on PCA-transformed training data'
        assert list(y) == list(state['train_y']), 'LogisticRegression must use training labels'
        state['model_fit_train'] = True
        return original_lr_fit(self, X, y, *args, **kwargs)

    def checked_lr_predict(self, X, *args, **kwargs):
        assert state['pca_test'] is not None and matrix_equal(X, state['pca_test']), \
            'Predictions must be made on PCA-transformed test data'
        state['model_predict_test'] = True
        return original_lr_predict(self, X, *args, **kwargs)

    monkeypatch.setattr(model_selection, 'train_test_split', checked_split)
    monkeypatch.setattr(text_module.TfidfVectorizer, 'fit', checked_tfidf_fit)
    monkeypatch.setattr(text_module.TfidfVectorizer, 'fit_transform', checked_tfidf_fit_transform)
    monkeypatch.setattr(text_module.TfidfVectorizer, 'transform', checked_tfidf_transform)
    monkeypatch.setattr(decomposition_module.PCA, 'fit', checked_pca_fit)
    monkeypatch.setattr(decomposition_module.PCA, 'fit_transform', checked_pca_fit_transform)
    monkeypatch.setattr(decomposition_module.PCA, 'transform', checked_pca_transform)
    monkeypatch.setattr(linear_model_module.LogisticRegression, 'fit', checked_lr_fit)
    monkeypatch.setattr(linear_model_module.LogisticRegression, 'predict', checked_lr_predict)

    original_data = open(DATA, 'rb').read()
    try:
        challenge.to_csv(DATA, index=False)
        if os.path.exists(METRICS):
            os.remove(METRICS)
        runpy.run_path(PIPELINE, run_name='__main__')

        assert state['split'], 'The executed pipeline did not split the raw data'
        assert state['vectorizer_fit_train'], 'TF-IDF was not fitted on training data'
        assert state['vectorizer_train_transformed'], 'Training text was not transformed by TF-IDF'
        assert state['vectorizer_test_transformed'], 'Test text was not transformed by the fitted TF-IDF vectorizer'
        assert state['pca_fit_train'], 'PCA was not fitted on training data'
        assert state['pca_train_transformed'], 'Training data was not transformed by PCA'
        assert state['pca_test_transformed'], 'Test data was not transformed by the fitted PCA model'
        assert state['model_fit_train'], 'LogisticRegression was not fitted on training data'
        assert state['model_predict_test'], 'LogisticRegression did not predict the test data'

        # Preserve and strengthen the original metrics assertions.
        assert os.path.exists(METRICS), f'Missing file: {METRICS}'
        try:
            with open(METRICS, 'r') as f:
                metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f'{METRICS} is not a valid JSON file.'

        assert 'test_accuracy' in metrics, "Missing 'test_accuracy' key in metrics.json"
        assert 'first_5_predictions' in metrics, "Missing 'first_5_predictions' key in metrics.json"
        assert isinstance(metrics['test_accuracy'], float), "'test_accuracy' must be a float"
        assert isinstance(metrics['first_5_predictions'], list), "'first_5_predictions' must be a list"
        assert len(metrics['first_5_predictions']) == 5, "'first_5_predictions' must contain exactly 5 elements"
        assert all(isinstance(x, int) for x in metrics['first_5_predictions']), 'All predictions must be integers'
        assert abs(metrics['test_accuracy'] - expected_accuracy) < 1e-12, \
            'test_accuracy does not match the independently recomputed test accuracy'
        assert metrics['first_5_predictions'] == [int(x) for x in expected_predictions[:5]], \
            'first_5_predictions does not match the independently recomputed predictions'
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
