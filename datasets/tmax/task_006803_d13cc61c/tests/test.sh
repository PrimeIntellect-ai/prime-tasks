#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUN_EOF' > /tmp/instrument_train.py
import os
import runpy
import numpy as np
import sklearn.datasets as datasets
import sklearn.model_selection as model_selection
import sklearn.preprocessing as preprocessing
import sklearn.linear_model as linear_model
import sklearn.metrics as metrics

make_calls = []
split_calls = []
scaler_fit_calls = []
scaler_transform_calls = []
model_init_calls = []
model_fit_calls = []
model_predict_calls = []
accuracy_calls = []

orig_make = datasets.make_classification
orig_split = model_selection.train_test_split
orig_scaler_fit = preprocessing.StandardScaler.fit
orig_scaler_transform = preprocessing.StandardScaler.transform
orig_lr = linear_model.LogisticRegression
orig_lr_fit = orig_lr.fit
orig_lr_predict = orig_lr.predict
orig_accuracy = metrics.accuracy_score

def snapshot(value):
    return np.asarray(value).copy()

def checked_make(*args, **kwargs):
    result = orig_make(*args, **kwargs)
    make_calls.append((args, dict(kwargs), snapshot(result[0]), snapshot(result[1])))
    return result

def checked_split(*args, **kwargs):
    result = orig_split(*args, **kwargs)
    split_calls.append((tuple(snapshot(x) for x in args[:2]), dict(kwargs), tuple(snapshot(x) for x in result)))
    return result

def checked_scaler_fit(self, X, *args, **kwargs):
    scaler_fit_calls.append(snapshot(X))
    return orig_scaler_fit(self, X, *args, **kwargs)

def checked_scaler_transform(self, X, *args, **kwargs):
    scaler_transform_calls.append(snapshot(X))
    return orig_scaler_transform(self, X, *args, **kwargs)

def checked_lr(*args, **kwargs):
    model_init_calls.append((args, dict(kwargs)))
    return orig_lr(*args, **kwargs)

def checked_lr_fit(self, X, y, *args, **kwargs):
    model_fit_calls.append((snapshot(X), snapshot(y)))
    return orig_lr_fit(self, X, y, *args, **kwargs)

def checked_lr_predict(self, X, *args, **kwargs):
    model_predict_calls.append(snapshot(X))
    return orig_lr_predict(self, X, *args, **kwargs)

def checked_accuracy(y_true, y_pred, *args, **kwargs):
    accuracy_calls.append((snapshot(y_true), snapshot(y_pred)))
    return orig_accuracy(y_true, y_pred, *args, **kwargs)

datasets.make_classification = checked_make
model_selection.train_test_split = checked_split
preprocessing.StandardScaler.fit = checked_scaler_fit
preprocessing.StandardScaler.transform = checked_scaler_transform
linear_model.LogisticRegression = checked_lr
orig_lr.fit = checked_lr_fit
orig_lr.predict = checked_lr_predict
metrics.accuracy_score = checked_accuracy

runpy.run_path('/home/user/train.py', run_name='__main__')

def require(condition, message):
    if not condition:
        raise AssertionError(message)

require(len(make_calls) == 1, 'The script must generate the configured dataset exactly once.')
make_args, make_kwargs, generated_X, generated_y = make_calls[0]
require(make_args == (), 'Dataset generation parameters must not be changed or supplied differently.')
require(make_kwargs == {
    'n_samples': 200,
    'n_features': 50,
    'n_informative': 10,
    'random_state': 123,
}, 'Dataset generation parameters or random seed were changed.')

require(len(split_calls) == 1, 'The script must perform the configured train/test split exactly once.')
split_inputs, split_kwargs, split_outputs = split_calls[0]
require(split_kwargs == {'test_size': 0.5, 'random_state': 123}, 'Split ratio or random seed was changed.')
require(np.array_equal(split_inputs[0], generated_X) and np.array_equal(split_inputs[1], generated_y),
        'The raw generated data must be split before feature scaling.')
X_train, X_test, y_train, y_test = split_outputs

require(len(scaler_fit_calls) == 1, 'StandardScaler must be fitted exactly once.')
require(np.array_equal(scaler_fit_calls[0], X_train),
        'StandardScaler must be fitted only on X_train.')
require(any(np.array_equal(x, X_train) for x in scaler_transform_calls), 'X_train was not transformed by the fitted scaler.')
require(any(np.array_equal(x, X_test) for x in scaler_transform_calls), 'X_test was not transformed by the fitted scaler.')

canonical_scaler = preprocessing.StandardScaler()
orig_scaler_fit(canonical_scaler, X_train)
expected_train = orig_scaler_transform(canonical_scaler, X_train)
expected_test = orig_scaler_transform(canonical_scaler, X_test)

require(len(model_init_calls) == 1, 'LogisticRegression must be constructed exactly once.')
require(model_init_calls[0] == ((), {'random_state': 123}), 'LogisticRegression hyperparameters or random seed were changed.')
require(len(model_fit_calls) == 1, 'LogisticRegression must be fitted exactly once.')
require(np.allclose(model_fit_calls[0][0], expected_train) and np.array_equal(model_fit_calls[0][1], y_train),
        'The model must be fitted on the correctly scaled training set and y_train.')
require(len(model_predict_calls) == 1 and np.allclose(model_predict_calls[0], expected_test),
        'Predictions must be made on X_test transformed by the training-fitted scaler.')
require(len(accuracy_calls) == 1 and np.array_equal(accuracy_calls[0][0], y_test),
        'Accuracy must be calculated against y_test.')
require(os.path.isfile('/home/user/accuracy.txt'), 'Running train.py did not generate accuracy.txt.')
RUN_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
import pytest
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

@pytest.fixture(scope='session', autouse=True)
def execute_and_validate_script():
    accuracy_file = '/home/user/accuracy.txt'
    if os.path.exists(accuracy_file):
        os.remove(accuracy_file)
    result = subprocess.run(
        ['python3', '/tmp/instrument_train.py'],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, 'Executing and validating /home/user/train.py failed:\n' + result.stdout

def expected_accuracy():
    X, y = make_classification(n_samples=200, n_features=50, n_informative=10, random_state=123)
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.5, random_state=123)
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_test = scaler.transform(X_test)
    clf = LogisticRegression(random_state=123)
    clf.fit(X_train, y_train)
    return f'{accuracy_score(y_test, clf.predict(X_test)):.4f}'

def test_accuracy_file():
    accuracy_file = '/home/user/accuracy.txt'
    assert os.path.isfile(accuracy_file), f'The file {accuracy_file} does not exist. Did you run the modified script?'

    with open(accuracy_file, 'r') as f:
        content = f.read().strip()

    assert content == '0.7700', f"Expected accuracy to be '0.7700' after fixing data leakage, but got '{content}'. Ensure the scaler is only fitted on the training data."
    assert content == expected_accuracy(), 'accuracy.txt does not contain the independently derived leakage-free accuracy.'

def test_train_script_fixed():
    script_path = '/home/user/train.py'
    assert os.path.isfile(script_path), f'The script {script_path} does not exist.'

    with open(script_path, 'r') as f:
        content = f.read()

    assert 'scaler.fit_transform(X)' not in content, 'The script still contains data leakage: `scaler.fit_transform(X)` was found before splitting.'
    assert 'scaler.fit(X)' not in content, 'The script still contains data leakage: `scaler.fit(X)` was found before splitting.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
