#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import joblib
import numpy as np
import pytest
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer

RAW = Path('/home/user/data/raw.jsonl')
FEATURES = Path('/home/user/data/features.npy')
VECTORIZER = Path('/home/user/models/vectorizer.joblib')
SVD = Path('/home/user/models/svd.joblib')
RESULT = Path('/home/user/test_result.txt')
METRICS = Path('/home/user/metrics.json')
ETL = Path('/home/user/etl.py')
REPRO = Path('/home/user/reproducibility_test.py')
BENCHMARK = Path('/home/user/benchmark.py')


def run_script(path, env=None, timeout=120):
    proc = subprocess.run(
        [sys.executable, str(path)],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert proc.returncode == 0, (
        f'{path} failed with exit code {proc.returncode}\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    return proc


def load_texts():
    texts = []
    with RAW.open() as f:
        for line in f:
            obj = json.loads(line)
            texts.append(obj['text'].lower().strip())
    return texts


def expected_pipeline():
    texts = load_texts()
    vectorizer = TfidfVectorizer(max_features=100, stop_words='english')
    tfidf = vectorizer.fit_transform(texts)
    svd = TruncatedSVD(n_components=10, random_state=42)
    features = svd.fit_transform(tfidf)
    return texts, vectorizer, svd, features


def assert_semantic_artifacts():
    texts, expected_vec, expected_svd, expected_features = expected_pipeline()
    assert FEATURES.is_file(), f'File {FEATURES} is missing'
    assert VECTORIZER.is_file(), f'Model file {VECTORIZER} is missing'
    assert SVD.is_file(), f'Model file {SVD} is missing'

    features = np.load(FEATURES, allow_pickle=False)
    assert features.shape == (len(texts), 10)
    assert np.issubdtype(features.dtype, np.number)
    assert np.all(np.isfinite(features))
    assert np.allclose(features, expected_features, rtol=1e-10, atol=1e-10)

    vectorizer = joblib.load(VECTORIZER)
    svd = joblib.load(SVD)
    assert isinstance(vectorizer, TfidfVectorizer)
    assert isinstance(svd, TruncatedSVD)
    assert vectorizer.max_features == 100
    assert vectorizer.stop_words == 'english'
    assert svd.n_components == 10
    assert svd.random_state == 42
    assert vectorizer.vocabulary_ == expected_vec.vocabulary_
    assert np.allclose(svd.components_, expected_svd.components_, rtol=1e-10, atol=1e-10)

    transformed = svd.transform(vectorizer.transform(texts))
    assert transformed.shape == features.shape
    assert np.allclose(features, transformed, rtol=1e-10, atol=1e-10)


def test_scripts_execute_and_artifacts_are_genuine(tmp_path):
    for script in (ETL, REPRO, BENCHMARK):
        assert script.is_file(), f'Required script {script} is missing'

    # Execute ETL from a clean artifact state and independently derive its answer.
    for path in (FEATURES, VECTORIZER, SVD):
        if path.exists():
            path.unlink()
    run_script(ETL)
    assert_semantic_artifacts()

    # Make every SVD transformation intentionally different. A real
    # reproducibility test must execute ETL twice, compare the two matrices,
    # and report FAIL rather than merely writing a literal PASS.
    patch_dir = tmp_path / 'patch'
    patch_dir.mkdir()
    counter = tmp_path / 'svd_count.txt'
    (patch_dir / 'sitecustomize.py').write_text(r'''import os
import numpy as np
import sklearn.decomposition as dec
import sklearn.decomposition._truncated_svd as impl

_counter = os.environ['VERIFIER_SVD_COUNTER']
_cls = impl.TruncatedSVD
_orig_ft = _cls.fit_transform
_orig_t = _cls.transform

def _bump(value):
    try:
        with open(_counter, 'r') as f:
            n = int(f.read().strip() or '0')
    except FileNotFoundError:
        n = 0
    n += 1
    with open(_counter, 'w') as f:
        f.write(str(n))
    return np.asarray(value) + n * 0.25

def fit_transform(self, X, y=None):
    return _bump(_orig_ft(self, X, y))

def transform(self, X):
    return _bump(_orig_t(self, X))

_cls.fit_transform = fit_transform
_cls.transform = transform
dec.TruncatedSVD = _cls
impl.TruncatedSVD = _cls
''')
    env = os.environ.copy()
    env['PYTHONPATH'] = str(patch_dir) + os.pathsep + env.get('PYTHONPATH', '')
    env['VERIFIER_SVD_COUNTER'] = str(counter)
    if RESULT.exists():
        RESULT.unlink()
    run_script(REPRO, env=env)
    assert counter.exists(), 'Reproducibility script did not execute the ETL SVD transformation'
    assert int(counter.read_text()) >= 2, 'Reproducibility script did not execute ETL twice'
    assert RESULT.is_file()
    assert RESULT.read_text().strip() == 'FAIL', 'Reproducibility script did not detect unequal runs'

    # Run normally and require both PASS and genuine regenerated artifacts.
    for path in (FEATURES, VECTORIZER, SVD, RESULT):
        if path.exists():
            path.unlink()
    run_script(REPRO)
    assert RESULT.read_text().strip() == 'PASS'
    assert_semantic_artifacts()

    # Replace the models temporarily with instrumented transform-only models.
    # This verifies that benchmark.py loads both files, supplies exactly the
    # preprocessed dataset, chains the transforms, and performs 50 iterations.
    spy_module = Path('/home/user/_verifier_benchmark_spy.py')
    spy_log = tmp_path / 'benchmark_calls.jsonl'
    spy_module.write_text(r'''import json
import numpy as np

class VectorizerSpy:
    def __init__(self, expected, log):
        self.expected = expected
        self.log = log
    def fit(self, *args, **kwargs):
        raise AssertionError('benchmark must not fit the vectorizer')
    def fit_transform(self, *args, **kwargs):
        raise AssertionError('benchmark must not fit the vectorizer')
    def transform(self, texts):
        texts = list(texts)
        if texts != self.expected:
            raise AssertionError('benchmark used incorrect or unpreprocessed text')
        with open(self.log, 'a') as f:
            f.write(json.dumps({'kind': 'vectorizer', 'rows': len(texts)}) + '\n')
        return np.full((len(texts), 4), 314159.0)

class SVDSpy:
    def __init__(self, expected_rows, log):
        self.expected_rows = expected_rows
        self.log = log
    def fit(self, *args, **kwargs):
        raise AssertionError('benchmark must not fit SVD')
    def fit_transform(self, *args, **kwargs):
        raise AssertionError('benchmark must not fit SVD')
    def transform(self, value):
        value = np.asarray(value)
        if value.shape != (self.expected_rows, 4) or not np.all(value == 314159.0):
            raise AssertionError('benchmark did not pass vectorizer output to SVD')
        with open(self.log, 'a') as f:
            f.write(json.dumps({'kind': 'svd', 'rows': self.expected_rows}) + '\n')
        return np.zeros((self.expected_rows, 10))
''')
    sys.path.insert(0, '/home/user')
    try:
        import _verifier_benchmark_spy as spy
        texts = load_texts()
        vec_backup = tmp_path / 'vectorizer.joblib'
        svd_backup = tmp_path / 'svd.joblib'
        shutil.copy2(VECTORIZER, vec_backup)
        shutil.copy2(SVD, svd_backup)
        try:
            joblib.dump(spy.VectorizerSpy(texts, str(spy_log)), VECTORIZER)
            joblib.dump(spy.SVDSpy(len(texts), str(spy_log)), SVD)
            if METRICS.exists():
                METRICS.unlink()
            run_script(BENCHMARK)
            calls = [json.loads(line) for line in spy_log.read_text().splitlines()]
            assert len(calls) == 100
            assert [c['kind'] for c in calls] == ['vectorizer', 'svd'] * 50
            assert all(c['rows'] == len(texts) for c in calls)
            instrumented_metrics = json.loads(METRICS.read_text())
            assert set(instrumented_metrics) == {'num_runs', 'avg_time_seconds'}
            assert instrumented_metrics['num_runs'] == 50
            assert isinstance(instrumented_metrics['avg_time_seconds'], (float, int))
            assert not isinstance(instrumented_metrics['avg_time_seconds'], bool)
            assert math.isfinite(instrumented_metrics['avg_time_seconds'])
            assert instrumented_metrics['avg_time_seconds'] >= 0
        finally:
            shutil.copy2(vec_backup, VECTORIZER)
            shutil.copy2(svd_backup, SVD)
    finally:
        if '/home/user' in sys.path:
            sys.path.remove('/home/user')
        sys.modules.pop('_verifier_benchmark_spy', None)
        if spy_module.exists():
            spy_module.unlink()

    # Produce and validate the requested final benchmark using the real models.
    if METRICS.exists():
        METRICS.unlink()
    run_script(BENCHMARK)
    metrics = json.loads(METRICS.read_text())
    assert set(metrics) == {'num_runs', 'avg_time_seconds'}
    assert metrics['num_runs'] == 50
    assert isinstance(metrics['avg_time_seconds'], (float, int))
    assert not isinstance(metrics['avg_time_seconds'], bool)
    assert math.isfinite(metrics['avg_time_seconds'])
    assert metrics['avg_time_seconds'] >= 0


# Preserve the original verifier's assertions.
def test_features_npy():
    features_path = '/home/user/data/features.npy'
    assert os.path.exists(features_path), f'File {features_path} is missing'
    raw_data_path = '/home/user/data/raw.jsonl'
    assert os.path.exists(raw_data_path), f'Raw data file {raw_data_path} is missing'
    with open(raw_data_path, 'r') as f:
        num_rows = sum(1 for _ in f)
    features = np.load(features_path)
    expected_shape = (num_rows, 10)
    assert features.shape == expected_shape, f'Expected features shape {expected_shape}, got {features.shape}'


def test_models_exist():
    vectorizer_path = '/home/user/models/vectorizer.joblib'
    svd_path = '/home/user/models/svd.joblib'
    assert os.path.exists(vectorizer_path), f'Model file {vectorizer_path} is missing'
    assert os.path.exists(svd_path), f'Model file {svd_path} is missing'


def test_reproducibility_result():
    result_path = '/home/user/test_result.txt'
    assert os.path.exists(result_path), f'Result file {result_path} is missing'
    with open(result_path, 'r') as f:
        res = f.read().strip()
    assert res == 'PASS', f"Reproducibility test failed, expected 'PASS' but got '{res}'"


def test_metrics_json():
    metrics_path = '/home/user/metrics.json'
    assert os.path.exists(metrics_path), f'File {metrics_path} is missing'
    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {metrics_path} does not contain valid JSON')
    assert 'num_runs' in metrics, "Key 'num_runs' is missing in metrics.json"
    assert metrics['num_runs'] == 50, f"Expected 'num_runs' to be 50, got {metrics['num_runs']}"
    assert 'avg_time_seconds' in metrics, "Key 'avg_time_seconds' is missing in metrics.json"
    assert isinstance(metrics['avg_time_seconds'], float) or isinstance(metrics['avg_time_seconds'], int), 'avg_time_seconds must be a number'
    assert metrics['avg_time_seconds'] >= 0, 'avg_time_seconds must be greater than or equal to 0'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
