#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import io
import json
import math
import os
import pwd
import random
import secrets
import shutil
import subprocess
import tempfile

HOME = '/home/user'
RAW = '/home/user/raw_data.csv'
NEW = '/home/user/new_batch.csv'
RESULT = '/home/user/pipeline_results.json'
VENV = '/home/user/etl_env'
PYTHON = VENV + '/bin/python'


def read_backup(path):
    if os.path.isfile(path) and not os.path.islink(path):
        with open(path, 'rb') as f:
            return True, f.read()
    return False, b''


def restore(path, backup):
    existed, data = backup
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    if existed:
        with open(path, 'wb') as f:
            f.write(data)


raw_backup = read_backup(RAW)
new_backup = read_backup(NEW)
result_backup = read_backup(RESULT)


def schema_features(raw_bytes):
    rows = list(csv.DictReader(io.StringIO(raw_bytes.decode('utf-8'))))
    valid = []
    for row in rows:
        try:
            if row.get('user_id') is None or row['user_id'].strip() == '':
                continue
            age = float(row['age'])
            income = float(row['annual_income'])
            if not math.isfinite(age) or age != int(age) or not 18 <= age <= 100:
                continue
            if not math.isfinite(income) or income <= 0:
                continue
            if row.get('profession') not in ['Engineer', 'Doctor', 'Artist', 'Teacher']:
                continue
            valid.append([float(age), float(income)])
        except (TypeError, ValueError, KeyError):
            continue
    return len(rows) - len(valid), valid


def batch_features(batch_bytes):
    rows = list(csv.DictReader(io.StringIO(batch_bytes.decode('utf-8'))))
    return [[float(r['age']), float(r['annual_income'])] for r in rows]


def csv_bytes(rows):
    out = io.StringIO(newline='')
    writer = csv.writer(out, lineterminator='\n')
    writer.writerow(['user_id', 'age', 'annual_income', 'profession'])
    writer.writerows(rows)
    return out.getvalue().encode('utf-8')


def make_case():
    rng = random.Random(secrets.randbits(64))
    professions = ['Engineer', 'Doctor', 'Artist', 'Teacher']
    rows = []
    valid_count = rng.randint(18, 31)
    base_income = rng.randint(35000, 65000)
    for i in range(valid_count):
        age = rng.randint(20, 68)
        income = base_income + age * rng.randint(700, 1350) + rng.randint(-5000, 5000)
        rows.append([1000 + i, age, income, professions[i % 4]])

    invalid = [
        ['', 30, 50000, 'Engineer'],
        [2001, '', 50000, 'Doctor'],
        [2002, 'not-a-number', 50000, 'Artist'],
        [2003, '25.5', 50000, 'Teacher'],
        [2004, 17, 50000, 'Engineer'],
        [2005, 101, 50000, 'Doctor'],
        [2006, 30, '', 'Artist'],
        [2007, 30, 'bad-income', 'Teacher'],
        [2008, 30, 0, 'Engineer'],
        [2009, 30, -100, 'Doctor'],
        [2010, 30, 50000, 'Hacker'],
        [2011, 30, 50000, ''],
    ]
    for j in range(rng.randint(0, 5)):
        invalid.append([3000 + j, rng.choice([10, 150, 'bad']), 60000, 'Engineer'])
    rows.extend(invalid)
    rng.shuffle(rows)

    batch = []
    for i in range(rng.randint(7, 13)):
        if i < 2:
            age = rng.choice([18, 95, 100])
            income = rng.choice([500000, 900000, 1500000])
        else:
            age = rng.randint(22, 66)
            income = base_income + age * rng.randint(700, 1350) + rng.randint(-7000, 7000)
        batch.append([5000 + i, age, income, professions[i % 4]])
    return csv_bytes(rows), csv_bytes(batch)


def reference_anomalies(fit_features, predict_features):
    code = r'''
import json, sys
from sklearn.ensemble import IsolationForest
payload = json.load(sys.stdin)
model = IsolationForest(random_state=42, contamination=0.1)
model.fit(payload["fit"])
predictions = model.predict(payload["predict"])
print(sum(int(x) == -1 for x in predictions))
'''
    proc = subprocess.run(
        [PYTHON, '-c', code],
        input=json.dumps({'fit': fit_features, 'predict': predict_features}),
        text=True, capture_output=True, timeout=60
    )
    assert proc.returncode == 0, 'The requested scikit-learn installation is not usable: ' + proc.stderr
    return int(proc.stdout.strip())


def arrays_equal(left, right):
    if len(left) != len(right):
        return False
    for a, b in zip(left, right):
        if len(a) != len(b):
            return False
        for x, y in zip(a, b):
            try:
                if not math.isclose(float(x), float(y), rel_tol=1e-10, abs_tol=1e-8):
                    return False
            except (TypeError, ValueError):
                return False
    return True


def validate_json(expected):
    assert os.path.exists(RESULT), f'File {RESULT} is missing. The script did not create the required output file.'
    assert os.path.isfile(RESULT) and not os.path.islink(RESULT), f'File {RESULT} must be a regular JSON file.'
    with open(RESULT, 'r', encoding='utf-8') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {RESULT} does not contain valid JSON.'
    expected_keys = ['invalid_rows_dropped', 'valid_rows_trained', 'anomalies_detected']
    for key in expected_keys:
        assert key in results, f"Key '{key}' is missing from the JSON results."
    assert set(results) == set(expected_keys), 'The JSON must contain exactly the three required keys.'
    for key in expected_keys:
        assert type(results[key]) is int, f"Value for '{key}' must be an integer."
    assert results['invalid_rows_dropped'] == expected[0], f"Expected {expected[0]} invalid_rows_dropped, got {results['invalid_rows_dropped']}"
    assert results['valid_rows_trained'] == expected[1], f"Expected {expected[1]} valid_rows_trained, got {results['valid_rows_trained']}"
    assert results['anomalies_detected'] == expected[2], f"Expected {expected[2]} anomalies_detected, got {results['anomalies_detected']}"


def run_script(script, raw_bytes, new_bytes, expected_fit, expected_predict, expected):
    with open(RAW, 'wb') as f:
        f.write(raw_bytes)
    with open(NEW, 'wb') as f:
        f.write(new_bytes)
    if os.path.lexists(RESULT):
        if os.path.isdir(RESULT) and not os.path.islink(RESULT):
            shutil.rmtree(RESULT)
        else:
            os.unlink(RESULT)

    instrument = tempfile.mkdtemp(prefix='etl_verify_')
    os.chmod(instrument, 0o755)
    marker = os.path.join(instrument, 'events.jsonl')
    with open(marker, 'w'):
        pass
    os.chmod(marker, 0o666)
    sitecustomize = r'''
import inspect, json, os
import numpy as np
import sklearn.ensemble
_RealIsolationForest = sklearn.ensemble.IsolationForest
_counter = 0

def _write(event):
    with open(os.environ['ETL_VERIFY_MARKER'], 'a', encoding='utf-8') as f:
        f.write(json.dumps(event) + '\n')

class _TrackedIsolationForest:
    def __init__(self, inner, ident):
        self._inner = inner
        self._ident = ident
    def fit(self, X, y=None, **kwargs):
        _write({'event': 'fit', 'id': self._ident, 'data': np.asarray(X).tolist()})
        self._inner.fit(X, y, **kwargs)
        return self
    def predict(self, X):
        _write({'event': 'predict', 'id': self._ident, 'data': np.asarray(X).tolist()})
        return self._inner.predict(X)
    def __getattr__(self, name):
        return getattr(self._inner, name)

def _factory(*args, **kwargs):
    global _counter
    _counter += 1
    bound = inspect.signature(_RealIsolationForest).bind_partial(*args, **kwargs)
    bound.apply_defaults()
    event = {'event': 'construct', 'id': _counter,
             'random_state': bound.arguments.get('random_state'),
             'contamination': bound.arguments.get('contamination')}
    _write(event)
    return _TrackedIsolationForest(_RealIsolationForest(*args, **kwargs), _counter)

sklearn.ensemble.IsolationForest = _factory
'''
    with open(os.path.join(instrument, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env['PYTHONPATH'] = instrument
    env['ETL_VERIFY_MARKER'] = marker
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        proc = subprocess.run(
            [PYTHON, script], cwd=HOME, env=env, capture_output=True, text=True,
            timeout=90, preexec_fn=demote
        )
        assert proc.returncode == 0, f'Script failed under /home/user/etl_env/bin/python: {proc.stderr[-2000:]}'
        validate_json(expected)
        with open(marker, encoding='utf-8') as f:
            events = [json.loads(line) for line in f if line.strip()]
        constructors = {
            e['id'] for e in events
            if e.get('event') == 'construct'
            and e.get('random_state') == 42
            and e.get('contamination') == 0.1
        }
        assert constructors, 'The script did not construct IsolationForest with random_state=42 and contamination=0.1.'
        matched = False
        for ident in constructors:
            fits = [e for e in events if e.get('event') == 'fit' and e.get('id') == ident]
            predicts = [e for e in events if e.get('event') == 'predict' and e.get('id') == ident]
            if any(arrays_equal(e.get('data', []), expected_fit) for e in fits) and any(
                arrays_equal(e.get('data', []), expected_predict) for e in predicts
            ):
                matched = True
                break
        assert matched, 'IsolationForest was not fit on the schema-valid age/income rows and used to predict the new batch in the required order.'
    finally:
        shutil.rmtree(instrument, ignore_errors=True)


try:
    assert os.path.isdir(VENV), 'Virtual environment /home/user/etl_env is missing.'
    assert os.path.isfile(PYTHON) and os.access(PYTHON, os.X_OK), 'The virtual environment Python interpreter is missing.'
    env_check = r'''
import importlib.metadata, json, os, sys
import pandas, sklearn
print(json.dumps({
    'prefix': os.path.realpath(sys.prefix),
    'sklearn': importlib.metadata.version('scikit-learn'),
    'pandas': importlib.metadata.version('pandas')
}))
'''
    proc = subprocess.run([PYTHON, '-c', env_check], capture_output=True, text=True, timeout=30)
    assert proc.returncode == 0, 'pandas and scikit-learn must be installed and importable in /home/user/etl_env.'
    info = json.loads(proc.stdout.strip())
    assert info['prefix'] == os.path.realpath(VENV), 'The interpreter is not from /home/user/etl_env.'
    assert info['sklearn'] == '1.3.0', f"Expected scikit-learn 1.3.0, got {info['sklearn']}"
    assert info['pandas'], 'pandas is not installed in the virtual environment.'

    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != VENV and d not in {'.cache', '__pycache__'}]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path) and not os.path.islink(path) and os.path.getsize(path) > 0:
                candidates.append(path)
    assert candidates, 'No Python ETL script was created under /home/user.'
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)

    original_raw = raw_backup[1]
    original_new = new_backup[1]
    original_invalid, original_fit = schema_features(original_raw)
    original_predict = batch_features(original_new)
    assert original_invalid == 5 and len(original_fit) == 21

    cases = [(original_raw, original_new, original_fit, original_predict, (5, 21, 2))]
    for _ in range(2):
        raw_bytes, new_bytes = make_case()
        invalid, fit_features = schema_features(raw_bytes)
        predict_features = batch_features(new_bytes)
        anomalies = reference_anomalies(fit_features, predict_features)
        cases.append((raw_bytes, new_bytes, fit_features, predict_features,
                      (invalid, len(fit_features), anomalies)))

    failures = []
    passed = False
    for script in candidates:
        try:
            for case in cases:
                run_script(script, *case)
            passed = True
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')
    assert passed, 'No submitted Python script implements the required pipeline. ' + ' | '.join(failures[-5:])
finally:
    restore(RAW, raw_backup)
    restore(NEW, new_backup)
    restore(RESULT, result_backup)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
