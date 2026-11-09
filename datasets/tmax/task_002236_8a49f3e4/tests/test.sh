#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import importlib.metadata
import os
import pickle
import subprocess
import sys
import uuid

import joblib
import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.base import BaseEstimator


def test_setup_py_fixed():
    setup_path = '/app/datacleaner/setup.py'
    assert os.path.exists(setup_path), f'File {setup_path} is missing.'
    with open(setup_path, 'r') as f:
        content = f.read()
    assert 'broken-dep-123' not in content, "The invalid dependency 'broken-dep-123' was not removed from setup.py"


def test_datacleaner_is_installed():
    assert importlib.metadata.version('datacleaner'), 'datacleaner is not installed'
    from datacleaner.utils import clean_features
    sample = np.array([[2.0, -3.0, 0.5]])
    np.testing.assert_allclose(clean_features(sample), sample ** 2)


def test_filter_script_exists():
    script_path = '/home/user/filter.py'
    assert os.path.exists(script_path), f'Script {script_path} is missing.'
    assert os.path.isfile(script_path), f'{script_path} is not a regular file.'


def test_model_exists_is_fitted_and_perfect_on_training_data():
    model_path = '/home/user/model.pkl'
    assert os.path.isfile(model_path), f'File {model_path} is missing.'
    assert os.path.getsize(model_path) > 0, 'model.pkl is empty'
    try:
        model = joblib.load(model_path)
    except Exception:
        with open(model_path, 'rb') as f:
            model = pickle.load(f)
    assert isinstance(model, BaseEstimator), 'model.pkl does not contain a scikit-learn estimator'
    assert callable(getattr(model, 'predict', None)), 'Saved model has no predict method'

    from datacleaner.utils import clean_features
    train = pd.read_csv('/home/user/train_data.csv')
    assert list(train.columns) == ['f1', 'f2', 'f3', 'is_evil']
    predictions = np.asarray(model.predict(clean_features(train[['f1', 'f2', 'f3']])))
    labels = train['is_evil'].to_numpy()
    assert len(predictions) == len(labels)
    assert np.array_equal(predictions, labels), 'Saved model is not 100% accurate on the preprocessed training data'


def test_cross_validation_and_tuning_evidence():
    scripts = [p for p in glob.glob('/home/user/**/*.py', recursive=True)
               if os.path.realpath(p) != '/home/user/filter.py']
    contents = []
    for path in scripts:
        try:
            with open(path, 'r', encoding='utf-8') as f:
                contents.append(f.read())
        except (OSError, UnicodeError):
            pass
    text = '\n'.join(contents)

    try:
        model = joblib.load('/home/user/model.pkl')
    except Exception:
        with open('/home/user/model.pkl', 'rb') as f:
            model = pickle.load(f)
    model_name = type(model).__name__

    search_markers = ('GridSearchCV', 'RandomizedSearchCV', 'HalvingGridSearchCV', 'HalvingRandomSearchCV')
    cv_markers = search_markers + ('cross_val_score', 'cross_validate', 'KFold', 'StratifiedKFold')
    tuning_markers = search_markers + ('ParameterGrid', 'ParameterSampler')
    has_search_model = model_name in search_markers or hasattr(model, 'cv_results_')
    assert has_search_model or any(marker in text for marker in cv_markers), 'No evidence that cross-validation was used'
    assert has_search_model or any(marker in text for marker in tuning_markers), 'No evidence that hyperparameter tuning was used'


def _instrumentation_dir(tmp_path):
    instrument = tmp_path / 'instrument'
    instrument.mkdir()
    (instrument / 'sitecustomize.py').write_text(r'''
import os

def log(value):
    path = os.environ.get('FILTER_AUDIT_LOG')
    if path:
        with open(path, 'a') as f:
            f.write(value + '\n')

try:
    import datacleaner.utils as _du
    _original_clean = _du.clean_features
    def _tracked_clean(*args, **kwargs):
        log('clean_features')
        return _original_clean(*args, **kwargs)
    _du.clean_features = _tracked_clean
except Exception:
    pass

try:
    import pickle as _pickle
    _original_pickle_load = _pickle.load
    def _tracked_pickle_load(file, *args, **kwargs):
        if os.path.basename(str(getattr(file, 'name', ''))) == 'model.pkl':
            log('model_load')
        return _original_pickle_load(file, *args, **kwargs)
    _pickle.load = _tracked_pickle_load
except Exception:
    pass

try:
    import joblib as _joblib
    _original_joblib_load = _joblib.load
    def _tracked_joblib_load(filename, *args, **kwargs):
        if os.path.basename(str(getattr(filename, 'name', filename))) == 'model.pkl':
            log('model_load')
        return _original_joblib_load(filename, *args, **kwargs)
    _joblib.load = _tracked_joblib_load
except Exception:
    pass
''', encoding='utf-8')
    return instrument


def _run_filter(input_path, output_path, instrument, audit_log):
    env = os.environ.copy()
    env['FILTER_AUDIT_LOG'] = str(audit_log)
    env['PYTHONPATH'] = str(instrument) + os.pathsep + env.get('PYTHONPATH', '')
    result = subprocess.run(
        [sys.executable, '/home/user/filter.py', '--input', str(input_path), '--output', str(output_path)],
        capture_output=True, text=True, env=env, timeout=30
    )
    assert result.returncode == 0, f'Filter failed:\nstdout={result.stdout}\nstderr={result.stderr}'
    assert output_path.is_file(), 'Filter did not create the requested output file'
    events = audit_log.read_text().splitlines() if audit_log.exists() else []
    assert 'clean_features' in events, 'filter.py did not call datacleaner.utils.clean_features'
    assert 'model_load' in events, 'filter.py did not load /home/user/model.pkl using pickle or joblib'


def _assert_output_matches(output_path, expected):
    with open(output_path, newline='') as f:
        rows = list(csv.reader(f))
    assert rows, 'Output CSV is empty and has no header'
    assert rows[0] == ['f1', 'f2', 'f3'], 'Output header is not exactly f1,f2,f3'
    actual = pd.read_csv(output_path)
    assert list(actual.columns) == ['f1', 'f2', 'f3']
    assert_frame_equal(actual.reset_index(drop=True), expected.reset_index(drop=True),
                       check_dtype=False, check_exact=False, rtol=1e-12, atol=1e-12)


def test_adversarial_corpus_filtering(tmp_path):
    script_path = '/home/user/filter.py'
    assert os.path.exists(script_path), f'Script {script_path} is missing.'

    evil_files = glob.glob('/verifier/evil/*.csv')
    clean_files = glob.glob('/verifier/clean/*.csv')
    assert len(evil_files) > 0, 'No evil corpus files found.'
    assert len(clean_files) > 0, 'No clean corpus files found.'

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        output_file = tmp_path / f'out_evil_{os.path.basename(evil_file)}'
        result = subprocess.run([sys.executable, script_path, '--input', evil_file, '--output', str(output_file)],
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f'Script failed on {evil_file}:\n{result.stderr}'
        with open(output_file, 'r') as f:
            rows = list(csv.reader(f))
        if len(rows) > 1:
            evil_bypassed.append(os.path.basename(evil_file))
        assert rows and rows[0] == ['f1', 'f2', 'f3'], 'Evil-file output has the wrong header'

    for clean_file in clean_files:
        output_file = tmp_path / f'out_clean_{os.path.basename(clean_file)}'
        result = subprocess.run([sys.executable, script_path, '--input', clean_file, '--output', str(output_file)],
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f'Script failed on {clean_file}:\n{result.stderr}'
        with open(clean_file, 'r') as f:
            orig_rows = list(csv.reader(f))
        with open(output_file, 'r') as f:
            out_rows = list(csv.reader(f))
        if len(out_rows) != len(orig_rows):
            clean_modified.append(os.path.basename(clean_file))
        assert out_rows and out_rows[0] == ['f1', 'f2', 'f3'], 'Clean-file output has the wrong header'
        expected = pd.read_csv(clean_file)
        _assert_output_matches(output_file, expected)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {", ".join(evil_bypassed)}')
    if clean_modified:
        error_msgs.append(f'{len(clean_modified)} of {len(clean_files)} clean modified: {", ".join(clean_modified)}')
    if error_msgs:
        pytest.fail(' | '.join(error_msgs))


def test_randomized_mixed_inputs_and_required_runtime_use(tmp_path):
    rng = np.random.default_rng()
    instrument = _instrumentation_dir(tmp_path)

    for case in range(4):
        clean = np.round(rng.uniform(-1.0, 1.0, (37, 3)), 6)
        evil = np.round(rng.uniform(3.0, 5.0, (29, 3)), 6)
        values = np.vstack([clean, evil])
        labels = np.array([0] * len(clean) + [1] * len(evil))
        order = rng.permutation(len(values))
        frame = pd.DataFrame(values[order], columns=['f1', 'f2', 'f3'])
        shuffled_labels = labels[order]
        expected = frame.loc[shuffled_labels == 0, ['f1', 'f2', 'f3']].reset_index(drop=True)

        token = uuid.uuid4().hex
        input_path = tmp_path / f'{token}.csv'
        output_path = tmp_path / f'{uuid.uuid4().hex}.csv'
        audit_log = tmp_path / f'audit_{case}.log'
        frame.to_csv(input_path, index=False)

        _run_filter(input_path, output_path, instrument, audit_log)
        _assert_output_matches(output_path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
