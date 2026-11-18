#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import textwrap

import numpy as np

PROCESS = '/home/user/process.py'
RESULT = '/home/user/result.json'


def load_and_validate_result(path):
    assert os.path.isfile(path), f'Expected result file at {path} is missing.'
    with open(path, 'r') as f:
        data = json.load(f)

    assert 'peaks' in data, "The key 'peaks' is missing from the JSON output."
    peaks = data['peaks']
    assert isinstance(peaks, list), "'peaks' should be a list."
    assert len(peaks) == 3, f'Expected exactly 3 peaks, but found {len(peaks)}.'

    means = []
    for i, peak in enumerate(peaks):
        assert isinstance(peak, dict), f'Peak at index {i} is not a dictionary.'
        for key in ('mean_index', 'ci_lower', 'ci_upper'):
            assert key in peak, f"Peak at index {i} is missing '{key}'."
            value = peak[key]
            assert isinstance(value, (int, float)) and not isinstance(value, bool), \
                f'{key} at index {i} must be numeric.'
            assert math.isfinite(float(value)), f'{key} at index {i} must be finite.'
        assert peak['ci_lower'] <= peak['ci_upper'], \
            f'Invalid confidence interval at index {i}.'
        means.append(peak['mean_index'])

    assert means == sorted(means), 'Components are not sorted by mean peak index.'
    return data


def test_complete_processing_pipeline():
    assert os.path.isfile(PROCESS), f'Expected processing script at {PROCESS} is missing.'
    assert os.path.islink(PROCESS) is False, f'{PROCESS} must be a regular submitted script.'

    # Execute the submitted artifact against the real service.
    subprocess.run(['/app/start_services.sh'], check=True, timeout=30)
    subprocess.run(['python3', PROCESS], cwd='/home/user', check=True, timeout=900)

    real_result = load_and_validate_result(RESULT)

    # Preserve the original metric assertion.
    extracted_means = [p['mean_index'] for p in real_result['peaks']]
    true_means = [40, 90, 160]
    mae = sum(abs(e - t) for e, t in zip(extracted_means, true_means)) / 3.0
    assert mae <= 3.0, (
        f'MAE {mae} exceeds threshold 3.0. Extracted means: '
        f'{extracted_means}, Expected means: {true_means}'
    )

    saved_result = '/tmp/real_result.json'
    shutil.copyfile(RESULT, saved_result)

    audit_dir = '/tmp/pipeline_audit'
    shutil.rmtree(audit_dir, ignore_errors=True)
    os.makedirs(audit_dir)
    event_file = os.path.join(audit_dir, 'events.jsonl')

    sitecustomize = r'''
import json
import os
import numpy as np

EVENT_FILE = os.environ['PIPELINE_AUDIT_LOG']

def emit(kind, **values):
    with open(EVENT_FILE, 'a') as f:
        f.write(json.dumps({'kind': kind, **values}) + '\n')

# Supply an independently generated dataset through the required HTTP API.
_rng = np.random.default_rng(731942)
_n, _m = 45, 200
_x = np.arange(_m)
_centers = [33, 107, 173]
_widths = [4.5, 7.0, 9.0]
_components = np.array([
    np.exp(-((_x-c)**2)/(2*w*w)) for c, w in zip(_centers, _widths)
])
_weights = _rng.uniform(0.15, 1.2, size=(_n, 3))
_baseline = np.array([
    _rng.uniform(0, 7) + _rng.uniform(-0.08, 0.08)*_x
    + _rng.uniform(0, 0.0008)*_x**2 for _ in range(_n)
])
_SPECTRA = _weights @ _components + _baseline + _rng.normal(0, 0.025, (_n, _m))

import requests
class AuditResponse:
    status_code = 200
    def raise_for_status(self):
        return None
    def json(self):
        return {'spectra': _SPECTRA.tolist()}

def audit_get(url, *args, **kwargs):
    emit('request', url=str(url))
    if str(url) != 'http://127.0.0.1:5000/data':
        raise AssertionError('Processing script fetched data from the wrong URL')
    return AuditResponse()
requests.get = audit_get

import scipy.signal
_original_savgol = scipy.signal.savgol_filter
_FILTER_OUTPUTS = []
def audited_savgol(x, window_length, polyorder, deriv=0, delta=1.0,
                    axis=-1, mode='interp', cval=0.0):
    arr = np.asarray(x)
    axis_norm = axis if axis >= 0 else arr.ndim + axis
    valid = (window_length == 21 and polyorder == 3 and deriv == 2
             and axis_norm == arr.ndim - 1)
    emit('savgol', valid=bool(valid), shape=list(arr.shape))
    if not valid:
        raise AssertionError('Incorrect Savitzky-Golay parameters or axis')
    out = _original_savgol(x, window_length, polyorder, deriv=deriv,
                            delta=delta, axis=axis, mode=mode, cval=cval)
    _FILTER_OUTPUTS.append(np.asarray(out).copy())
    return out
scipy.signal.savgol_filter = audited_savgol

import sklearn.decomposition
_OriginalNMF = sklearn.decomposition.NMF
_BASE = None
_CALL = 0

class AuditedNMF:
    def __init__(self, *args, **kwargs):
        self._inner = _OriginalNMF(*args, **kwargs)
        if self._inner.n_components != 3:
            raise AssertionError('NMF must use exactly 3 components')

    def _check_input(self, X):
        global _BASE
        arr = np.asarray(X)
        if arr.ndim != 2 or arr.shape[1] != 200:
            raise AssertionError('NMF received an invalid matrix')
        if np.any(arr < -1e-12):
            raise AssertionError('NMF input is not non-negative')
        if _BASE is None:
            if not any(arr.shape == f.shape and np.allclose(arr, np.abs(f), rtol=1e-10, atol=1e-12)
                       for f in _FILTER_OUTPUTS):
                raise AssertionError('First NMF input is not abs(Savitzky-Golay output)')
            _BASE = arr.copy()
            return False
        if arr.shape != _BASE.shape:
            raise AssertionError('Bootstrap sample has the wrong shape')
        matches = np.array([np.any(np.all(np.isclose(_BASE, row, rtol=1e-10, atol=1e-12), axis=1))
                            for row in arr])
        if not np.all(matches):
            raise AssertionError('Bootstrap data was not made by resampling original rows')
        unique_rows = len({np.asarray(row).tobytes() for row in arr})
        return unique_rows < arr.shape[0]

    def _record(self, duplicate_rows):
        global _CALL
        self.components_ = self._inner.components_
        peaks = sorted(int(v) for v in np.argmax(self.components_, axis=1))
        emit('nmf', call=_CALL, peaks=peaks, duplicate_rows=bool(duplicate_rows))
        _CALL += 1

    def fit_transform(self, X, y=None, W=None, H=None):
        duplicate_rows = self._check_input(X)
        out = self._inner.fit_transform(X, y=y, W=W, H=H)
        self._record(duplicate_rows)
        return out

    def fit(self, X, y=None, **params):
        duplicate_rows = self._check_input(X)
        self._inner.fit(X, y=y, **params)
        self._record(duplicate_rows)
        return self

    def transform(self, X):
        return self._inner.transform(X)

    def __getattr__(self, name):
        return getattr(self._inner, name)

sklearn.decomposition.NMF = AuditedNMF
'''
    with open(os.path.join(audit_dir, 'sitecustomize.py'), 'w') as f:
        f.write(textwrap.dedent(sitecustomize))

    env = os.environ.copy()
    env['PYTHONPATH'] = audit_dir + os.pathsep + env.get('PYTHONPATH', '')
    env['PIPELINE_AUDIT_LOG'] = event_file

    try:
        subprocess.run(['python3', PROCESS], cwd='/home/user', env=env,
                       check=True, timeout=900)
        audited_result = load_and_validate_result(RESULT)

        with open(event_file) as f:
            events = [json.loads(line) for line in f if line.strip()]

        requests_seen = [e for e in events if e['kind'] == 'request']
        filters = [e for e in events if e['kind'] == 'savgol']
        fits = [e for e in events if e['kind'] == 'nmf']

        assert requests_seen, 'The script did not fetch the required HTTP endpoint.'
        assert filters and all(e['valid'] for e in filters), \
            'Required Savitzky-Golay preprocessing was not performed.'
        assert len(fits) == 101, \
            f'Expected one initial NMF fit and 100 bootstrap fits, observed {len(fits)}.'
        assert sum(bool(e['duplicate_rows']) for e in fits[1:]) >= 90, \
            'NMF bootstrap inputs do not show row resampling with replacement.'

        bootstrap_peaks = np.asarray([e['peaks'] for e in fits[1:]], dtype=float)
        expected_means = np.mean(bootstrap_peaks, axis=0)
        expected_lower = np.percentile(bootstrap_peaks, 2.5, axis=0)
        expected_upper = np.percentile(bootstrap_peaks, 97.5, axis=0)

        submitted = audited_result['peaks']
        assert np.allclose([p['mean_index'] for p in submitted], expected_means,
                           rtol=0, atol=1e-6), \
            'mean_index values were not computed from the 100 bootstrap NMF fits.'
        assert np.allclose([p['ci_lower'] for p in submitted], expected_lower,
                           rtol=0, atol=1e-6), \
            'ci_lower values are not the bootstrap 2.5th percentiles.'
        assert np.allclose([p['ci_upper'] for p in submitted], expected_upper,
                           rtol=0, atol=1e-6), \
            'ci_upper values are not the bootstrap 97.5th percentiles.'
    finally:
        shutil.copyfile(saved_result, RESULT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
