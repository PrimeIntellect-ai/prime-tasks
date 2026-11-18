#!/bin/bash
mkdir -p /logs/verifier /tmp/verifier_hooks

cat << 'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os

import scipy.sparse
import sklearn.model_selection as _ms
from sklearn.pipeline import Pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.neighbors import KNeighborsClassifier

_LOG = os.environ.get('AUDIT_LOG')
_REAL_SPLIT = _ms.train_test_split
_REAL_GRID = _ms.GridSearchCV


def _write(event):
    if _LOG:
        with open(_LOG, 'a') as f:
            f.write(json.dumps(event) + '\n')


def _is_raw_text(value):
    if scipy.sparse.issparse(value):
        return False
    try:
        first = value.iloc[0] if hasattr(value, 'iloc') else value[0]
    except Exception:
        return False
    return isinstance(first, str)


def audited_split(*args, **kwargs):
    test_size = kwargs.get('test_size', args[2] if len(args) > 2 else None)
    random_state = kwargs.get('random_state', args[4] if len(args) > 4 else None)
    _write({
        'event': 'split',
        'raw_text': bool(args and _is_raw_text(args[0])),
        'test_size': test_size,
        'random_state': random_state,
    })
    return _REAL_SPLIT(*args, **kwargs)


class _GridProxy:
    def __init__(self, wrapped):
        object.__setattr__(self, '_wrapped', wrapped)

    def fit(self, X, y=None, **kwargs):
        _write({'event': 'grid_fit', 'raw_text': _is_raw_text(X)})
        self._wrapped.fit(X, y, **kwargs)
        return self

    def __getattr__(self, name):
        return getattr(self._wrapped, name)

    def __setattr__(self, name, value):
        setattr(self._wrapped, name, value)


def audited_grid(*args, **kwargs):
    estimator = args[0] if args else kwargs.get('estimator')
    param_grid = args[1] if len(args) > 1 else kwargs.get('param_grid')
    cv = kwargs.get('cv')

    valid_pipeline = isinstance(estimator, Pipeline)
    valid_steps = False
    if valid_pipeline:
        steps = estimator.steps
        valid_steps = (
            len(steps) == 2 and
            steps[0][0] == 'tfidf' and isinstance(steps[0][1], TfidfVectorizer) and
            steps[1][0] == 'knn' and isinstance(steps[1][1], KNeighborsClassifier)
        )

    _write({
        'event': 'grid_init',
        'pipeline': valid_pipeline,
        'steps': valid_steps,
        'cv': cv,
        'param_grid': param_grid,
    })
    return _GridProxy(_REAL_GRID(*args, **kwargs))


_ms.train_test_split = audited_split
_ms.GridSearchCV = audited_grid
HOOK_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess
import sys

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import GridSearchCV, train_test_split
from sklearn.neighbors import KNeighborsClassifier
from sklearn.pipeline import Pipeline

DATA_PATH = '/home/user/data.csv'
RESULT_PATH = '/home/user/fixed_result.txt'
SCRIPT_PATH = '/home/user/train_model.py'
AUDIT_PATH = '/tmp/train_model_audit.jsonl'


def validate_result(expected_score=None, expected_params=None):
    # Preserve the original verifier's assertions.
    assert os.path.isfile(RESULT_PATH), f'Expected output file {RESULT_PATH} is missing.'
    with open(RESULT_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, 'The file should contain at least two lines for Test Score and Best Params.'
    score_line = lines[0]
    params_line = lines[1]
    assert score_line.startswith('Test Score:'), "The first line must start with 'Test Score:'"
    assert params_line.startswith('Best Params:'), "The second line must start with 'Best Params:'"

    score_match = re.search(r'Test Score:\s*([0-9]+\.[0-9]{4})$', score_line)
    assert score_match is not None, 'Test Score must be a number rounded to exactly 4 decimal places.'

    params_str = params_line.replace('Best Params:', '', 1).strip()
    try:
        params_dict = ast.literal_eval(params_str)
        assert isinstance(params_dict, dict), 'Best Params must be a valid Python dictionary.'
        assert 'tfidf__max_features' in params_dict, "Best Params dictionary is missing 'tfidf__max_features'."
        assert 'knn__n_neighbors' in params_dict, "Best Params dictionary is missing 'knn__n_neighbors'."
        assert params_dict['tfidf__max_features'] in [50, 100], 'tfidf__max_features must be chosen from [50, 100].'
        assert params_dict['knn__n_neighbors'] in [3, 5, 7], 'knn__n_neighbors must be chosen from [3, 5, 7].'
    except (SyntaxError, ValueError):
        raise AssertionError('The Best Params output is not a valid dictionary representation.')

    if expected_score is not None:
        assert score_line == f'Test Score: {expected_score:.4f}', 'Test Score does not match a leakage-free recomputation.'
        assert params_dict == expected_params, 'Best Params do not match a leakage-free recomputation.'


def reference_result(frame):
    X_train, X_test, y_train, y_test = train_test_split(
        frame['text'], frame['label'], test_size=0.2, random_state=42
    )
    pipeline = Pipeline([
        ('tfidf', TfidfVectorizer()),
        ('knn', KNeighborsClassifier()),
    ])
    grid = GridSearchCV(
        pipeline,
        {
            'tfidf__max_features': [50, 100],
            'knn__n_neighbors': [3, 5, 7],
        },
        cv=5,
    )
    grid.fit(X_train, y_train)
    return grid.score(X_test, y_test), grid.best_params_


def make_challenge():
    rng = np.random.RandomState(73129)
    rows = []
    for i in range(180):
        label = int(rng.randint(0, 2))
        class_words = [f'class{label}_{j}' for j in range(45)]
        other_words = [f'class{1-label}_{j}' for j in range(45)]
        common_words = [f'common_{j}' for j in range(50)]
        noise_words = [f'noise_{j}' for j in range(90)]
        tokens = list(rng.choice(class_words, 8))
        tokens += list(rng.choice(other_words, 2))
        tokens += list(rng.choice(common_words, 5))
        tokens += list(rng.choice(noise_words, 5))
        rng.shuffle(tokens)
        rows.append((' '.join(tokens), label))
    return pd.DataFrame(rows, columns=['text', 'label'])


def run_script(audited):
    assert os.path.isfile(SCRIPT_PATH), f'Expected script {SCRIPT_PATH} is missing.'
    env = os.environ.copy()
    if audited:
        env['PYTHONPATH'] = '/tmp/verifier_hooks'
        env['AUDIT_LOG'] = AUDIT_PATH
    else:
        env.pop('PYTHONPATH', None)
        env.pop('AUDIT_LOG', None)
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180,
    )
    assert completed.returncode == 0, 'train_model.py failed:\n' + completed.stderr


def validate_audit():
    assert os.path.isfile(AUDIT_PATH), 'The script did not exercise the audited scikit-learn APIs.'
    with open(AUDIT_PATH) as f:
        events = [json.loads(line) for line in f if line.strip()]

    splits = [e for e in events if e.get('event') == 'split']
    grids = [e for e in events if e.get('event') == 'grid_init']
    fits = [e for e in events if e.get('event') == 'grid_fit']

    assert any(e.get('raw_text') and e.get('test_size') == 0.2 and e.get('random_state') == 42 for e in splits), \
        'train_test_split must split raw text with test_size=0.2 and random_state=42.'
    assert grids, 'GridSearchCV was not constructed by the script.'
    assert any(
        e.get('pipeline') and e.get('steps') and e.get('cv') == 5 and
        e.get('param_grid') == {
            'tfidf__max_features': [50, 100],
            'knn__n_neighbors': [3, 5, 7],
        }
        for e in grids
    ), 'GridSearchCV must receive the required Pipeline, parameter grid, and cv=5.'
    assert any(e.get('raw_text') for e in fits), 'GridSearchCV must be fitted on untransformed training text.'


assert os.path.isfile(DATA_PATH), f'Expected data file {DATA_PATH} is missing.'
with open(DATA_PATH, 'rb') as f:
    original_data = f.read()
original_result = None
if os.path.isfile(RESULT_PATH):
    with open(RESULT_PATH, 'rb') as f:
        original_result = f.read()

try:
    # Retain checks against the output the agent generated before verification.
    validate_result()

    original_frame = pd.read_csv(DATA_PATH)
    original_expected = reference_result(original_frame)

    # Exercise the submitted script on verifier-generated data and independently
    # derive the correct score and parameters.
    challenge = make_challenge()
    challenge_expected = reference_result(challenge)
    challenge.to_csv(DATA_PATH, index=False)
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    if os.path.exists(AUDIT_PATH):
        os.remove(AUDIT_PATH)

    run_script(audited=True)
    validate_result(*challenge_expected)
    validate_audit()

    # Restore the task input, execute once more, and leave the required final output.
    with open(DATA_PATH, 'wb') as f:
        f.write(original_data)
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    run_script(audited=False)
    validate_result(*original_expected)
except Exception:
    with open(DATA_PATH, 'wb') as f:
        f.write(original_data)
    if original_result is None:
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
    else:
        with open(RESULT_PATH, 'wb') as f:
            f.write(original_result)
    raise
finally:
    with open(DATA_PATH, 'wb') as f:
        f.write(original_data)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
