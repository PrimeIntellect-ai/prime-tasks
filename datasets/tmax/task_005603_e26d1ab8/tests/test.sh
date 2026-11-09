#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import uuid

import pandas as pd
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

SCRIPT = '/home/user/evaluate.sh'
PIPELINE = '/home/user/pipeline.py'
DATA = '/home/user/data.csv'
OUTPUT = '/home/user/accuracy.txt'


def run_wrapper(env=None):
    return subprocess.run(['bash', SCRIPT], capture_output=True, text=True, env=env)


def read_float(path=OUTPUT):
    with open(path, 'r') as f:
        value = f.read().strip()
    try:
        return float(value)
    except ValueError:
        pytest.fail(f'{path} does not contain a valid float. Found: {value}')


def test_evaluate_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT), f'File not found: {SCRIPT}'
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f'{SCRIPT} is not executable'


def test_evaluate_sh_contents():
    with open(SCRIPT, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r'PYTHONHASHSEED\s*=\s*42', content), 'evaluate.sh does not export PYTHONHASHSEED=42'
    assert re.search(r'OMP_NUM_THREADS\s*=\s*1', content), 'evaluate.sh does not export OMP_NUM_THREADS=1'
    assert 'pipeline.py' in content, 'evaluate.sh does not execute pipeline.py'
    assert 'accuracy.txt' in content, 'evaluate.sh does not redirect output to accuracy.txt'


def test_pipeline_py_fixed_source_assertions():
    with open(PIPELINE, 'r') as f:
        content = f.read()

    # Preserve the original source assertions in addition to behavioral checks.
    assert not re.search(r'fit_transform\(\s*df\[', content), 'pipeline.py still fits on the entire dataset.'
    assert 'train_test_split' in content, 'train_test_split is missing.'
    assert (re.search(r'fit_transform\(.*train', content, re.IGNORECASE)
            or re.search(r'fit_transform\(.*X_train', content)), \
        'pipeline.py does not fit_transform on the training set.'


def test_wrapper_really_exports_and_redirects(monkeypatch):
    marker = 'wrapper-probe-' + uuid.uuid4().hex
    with open(PIPELINE, 'rb') as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(PIPELINE).st_mode)

    probe = (
        "import os\n"
        "assert os.environ.get('PYTHONHASHSEED') == '42'\n"
        "assert os.environ.get('OMP_NUM_THREADS') == '1'\n"
        f"print({marker!r})\n"
    ).encode()

    try:
        with open(PIPELINE, 'wb') as f:
            f.write(probe)
        os.chmod(PIPELINE, original_mode)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = run_wrapper()
        assert result.returncode == 0, f'evaluate.sh failed probe execution. Stderr: {result.stderr}'
        assert os.path.isfile(OUTPUT), f'{OUTPUT} was not created by evaluate.sh'
        with open(OUTPUT, 'r') as f:
            assert f.read().strip() == marker, \
                'evaluate.sh did not execute pipeline.py with its stdout redirected to accuracy.txt'
    finally:
        with open(PIPELINE, 'wb') as f:
            f.write(original)
        os.chmod(PIPELINE, original_mode)


def test_pipeline_behavior_and_genuine_accuracy(tmp_path):
    # Use verifier-selected data so a canned accuracy cannot satisfy the test.
    rows = []
    for i in range(40):
        if i % 2 == 0:
            rows.append({'text': f'excellent wonderful positive item token{i}', 'label': 1})
        else:
            rows.append({'text': f'terrible awful negative item token{i}', 'label': 0})
    frame = pd.DataFrame(rows)

    original_data = open(DATA, 'rb').read()
    events = tmp_path / 'events.jsonl'
    instrument = tmp_path / 'instrument'
    instrument.mkdir()
    sitecustomize = instrument / 'sitecustomize.py'
    sitecustomize.write_text(r'''
import functools
import json
import os

EVENTS = os.environ['PIPELINE_TEST_EVENTS']

def serial(value):
    if hasattr(value, 'tolist'):
        value = value.tolist()
    if isinstance(value, tuple):
        value = list(value)
    if isinstance(value, list):
        return [serial(x) for x in value]
    if hasattr(value, 'item'):
        try:
            return value.item()
        except Exception:
            pass
    return value

def log(kind, **values):
    with open(EVENTS, 'a') as f:
        f.write(json.dumps({'kind': kind, **{k: serial(v) for k, v in values.items()}}) + '\n')

import sklearn.model_selection as model_selection
_original_split = model_selection.train_test_split
@functools.wraps(_original_split)
def checked_split(*args, **kwargs):
    log('split_call', kwargs=kwargs)
    result = _original_split(*args, **kwargs)
    log('split_result', train=result[0], test=result[1], y_train=result[2], y_test=result[3])
    return result
model_selection.train_test_split = checked_split

import sklearn.feature_extraction.text as text_module
_original_vec_init = text_module.TfidfVectorizer.__init__
_original_fit_transform = text_module.TfidfVectorizer.fit_transform
_original_transform = text_module.TfidfVectorizer.transform
@functools.wraps(_original_vec_init)
def vec_init(self, *args, **kwargs):
    log('vec_init', args=args, kwargs=kwargs)
    return _original_vec_init(self, *args, **kwargs)
@functools.wraps(_original_fit_transform)
def fit_transform(self, raw_documents, *args, **kwargs):
    docs = list(raw_documents)
    log('fit_transform', documents=docs)
    return _original_fit_transform(self, docs, *args, **kwargs)
@functools.wraps(_original_transform)
def transform(self, raw_documents, *args, **kwargs):
    docs = list(raw_documents)
    log('transform', documents=docs)
    return _original_transform(self, docs, *args, **kwargs)
text_module.TfidfVectorizer.__init__ = vec_init
text_module.TfidfVectorizer.fit_transform = fit_transform
text_module.TfidfVectorizer.transform = transform

import sklearn.linear_model as linear_model
_original_lr_init = linear_model.LogisticRegression.__init__
@functools.wraps(_original_lr_init)
def lr_init(self, *args, **kwargs):
    log('lr_init', args=args, kwargs=kwargs)
    return _original_lr_init(self, *args, **kwargs)
linear_model.LogisticRegression.__init__ = lr_init

import sklearn.metrics as metrics
_original_accuracy = metrics.accuracy_score
@functools.wraps(_original_accuracy)
def checked_accuracy(y_true, y_pred, *args, **kwargs):
    value = _original_accuracy(y_true, y_pred, *args, **kwargs)
    log('accuracy_score', y_true=y_true, y_pred=y_pred, value=value)
    return value
metrics.accuracy_score = checked_accuracy
''')

    try:
        frame.to_csv(DATA, index=False)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        env = os.environ.copy()
        env['PIPELINE_TEST_EVENTS'] = str(events)
        old_pythonpath = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = str(instrument) + (os.pathsep + old_pythonpath if old_pythonpath else '')
        result = run_wrapper(env)
        assert result.returncode == 0, f'evaluate.sh failed to run. Stderr: {result.stderr}'
        assert os.path.isfile(OUTPUT), f'{OUTPUT} was not created by evaluate.sh'
        reported = read_float()
        assert 0.0 <= reported <= 1.0, f'Accuracy {reported} is out of bounds [0.0, 1.0]'
        assert events.is_file(), 'pipeline did not execute under Python instrumentation'

        parsed = [json.loads(line) for line in events.read_text().splitlines() if line.strip()]
        kinds = [event['kind'] for event in parsed]
        assert kinds.count('split_call') == 1, 'pipeline must perform exactly one train/test split'
        assert kinds.count('fit_transform') == 1, 'TF-IDF must be fitted exactly once'
        assert kinds.index('split_call') < kinds.index('fit_transform'), \
            'TF-IDF fitting occurred before the train/test split'

        split_call = next(event for event in parsed if event['kind'] == 'split_call')
        assert split_call['kwargs'] == {'test_size': 0.3, 'random_state': 42}, \
            'train_test_split must use only test_size=0.3 and random_state=42'

        split_result = next(event for event in parsed if event['kind'] == 'split_result')
        fit_event = next(event for event in parsed if event['kind'] == 'fit_transform')
        assert fit_event['documents'] == split_result['train'], \
            'TfidfVectorizer was not fitted exclusively on the training text'
        transformed = [event['documents'] for event in parsed if event['kind'] == 'transform']
        assert split_result['test'] in transformed, 'the held-out test text was not transformed'

        vec_init = next(event for event in parsed if event['kind'] == 'vec_init')
        assert vec_init['args'] == [] and vec_init['kwargs'] == {}, \
            'TfidfVectorizer hyperparameters were changed'
        lr_init = next(event for event in parsed if event['kind'] == 'lr_init')
        assert lr_init['args'] == [] and lr_init['kwargs'] == {'random_state': 42}, \
            'LogisticRegression must retain random_state=42 and its other default hyperparameters'

        accuracy_event = next(event for event in parsed if event['kind'] == 'accuracy_score')
        assert reported == pytest.approx(accuracy_event['value']), \
            'accuracy.txt does not contain the value computed by accuracy_score'

        train_text, test_text, train_y, test_y = train_test_split(
            frame['text'], frame['label'], test_size=0.3, random_state=42)
        vectorizer = TfidfVectorizer()
        train_x = vectorizer.fit_transform(train_text)
        test_x = vectorizer.transform(test_text)
        classifier = LogisticRegression(random_state=42)
        classifier.fit(train_x, train_y)
        expected = accuracy_score(test_y, classifier.predict(test_x))
        assert reported == pytest.approx(expected), \
            'reported accuracy does not match the required leak-free pipeline'
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)


# Retain a direct execution test on the restored, original dataset.
def test_evaluate_sh_execution():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = run_wrapper()
    assert result.returncode == 0, f'evaluate.sh failed to run. Stderr: {result.stderr}'
    assert os.path.isfile(OUTPUT), f'{OUTPUT} was not created by evaluate.sh'
    accuracy = read_float()
    assert 0.0 <= accuracy <= 1.0, f'Accuracy {accuracy} is out of bounds [0.0, 1.0]'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
