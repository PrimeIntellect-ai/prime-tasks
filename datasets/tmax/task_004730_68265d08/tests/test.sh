#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hooks
cat <<'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import functools
import inspect
import json
import os

LOG_PATH = os.environ.get("PIPELINE_CALL_LOG")

def record(event, **details):
    if not LOG_PATH:
        return
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps({"event": event, **details}) + "\n")
    except Exception:
        pass

try:
    import pandas as pd
    _read_csv = pd.read_csv

    @functools.wraps(_read_csv)
    def read_csv(*args, **kwargs):
        path = args[0] if args else kwargs.get("filepath_or_buffer")
        record("pandas.read_csv", path=os.path.abspath(os.fspath(path)) if isinstance(path, (str, bytes, os.PathLike)) else str(path))
        return _read_csv(*args, **kwargs)

    pd.read_csv = read_csv
except Exception:
    pass

try:
    from sklearn.preprocessing import StandardScaler
    from sklearn.decomposition import PCA
    from sklearn.ensemble import IsolationForest

    def wrap_init(cls, name):
        original = cls.__init__
        signature = inspect.signature(original)

        @functools.wraps(original)
        def wrapped(self, *args, **kwargs):
            values = {}
            try:
                bound = signature.bind(self, *args, **kwargs)
                bound.apply_defaults()
                values = {k: v for k, v in bound.arguments.items() if k != "self"}
            except Exception:
                values = dict(kwargs)
            record(name + ".init", n_components=values.get("n_components"), random_state=values.get("random_state"))
            return original(self, *args, **kwargs)

        cls.__init__ = wrapped

    def wrap_method(cls, method_name, event):
        original = getattr(cls, method_name, None)
        if original is None:
            return

        @functools.wraps(original)
        def wrapped(self, *args, **kwargs):
            record(event)
            return original(self, *args, **kwargs)

        setattr(cls, method_name, wrapped)

    wrap_init(PCA, "PCA")
    wrap_init(IsolationForest, "IsolationForest")
    for method in ("fit", "transform", "fit_transform"):
        wrap_method(StandardScaler, method, "StandardScaler." + method)
    for method in ("fit", "transform", "fit_transform", "inverse_transform"):
        wrap_method(PCA, method, "PCA." + method)
    for method in ("fit", "predict", "fit_predict"):
        wrap_method(IsolationForest, method, "IsolationForest." + method)
except Exception:
    pass
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import subprocess

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.ensemble import IsolationForest
from sklearn.metrics import mean_squared_error
from sklearn.preprocessing import StandardScaler

TELEMETRY = Path('/home/user/telemetry.csv')
METRICS = Path('/home/user/metrics.json')
CALL_LOG = Path('/tmp/pipeline_calls.jsonl')


def expected_metrics(frame):
    standardized = StandardScaler().fit_transform(frame)
    pca = PCA(n_components=5, random_state=42)
    reduced = pca.fit_transform(standardized)
    reconstructed = pca.inverse_transform(reduced)
    model = IsolationForest(random_state=42)
    model.fit(reduced)
    predictions = model.predict(reduced)
    return {
        'reconstruction_mse': round(float(mean_squared_error(standardized, reconstructed)), 4),
        'anomaly_count': int(np.sum(predictions == -1)),
    }


def load_and_assert_metrics(expected):
    # Preserve the original verifier's existence and file assertions.
    assert METRICS.exists(), f"The file {METRICS} is missing. Did you forget to export the results?"
    assert METRICS.is_file(), f"The path {METRICS} exists but is not a file."

    try:
        with METRICS.open('r', encoding='utf-8') as f:
            results = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"{METRICS} is not a valid JSON file.")

    assert 'reconstruction_mse' in results, "Key 'reconstruction_mse' missing from metrics.json"
    assert 'anomaly_count' in results, "Key 'anomaly_count' missing from metrics.json"

    mse = results['reconstruction_mse']
    anomaly_count = results['anomaly_count']
    assert isinstance(mse, float), f"'reconstruction_mse' should be a float, got {type(mse)}"
    assert isinstance(anomaly_count, int), f"'anomaly_count' should be an int, got {type(anomaly_count)}"
    assert abs(mse - expected['reconstruction_mse']) < 0.0002, \
        f"Expected reconstruction_mse to be close to {expected['reconstruction_mse']}, got {mse}"
    assert anomaly_count == expected['anomaly_count'], \
        f"Expected anomaly_count to be {expected['anomaly_count']}, got {anomaly_count}"


def assert_pipeline_calls():
    assert CALL_LOG.is_file(), 'The submitted script did not execute the required pipeline operations.'
    events = []
    with CALL_LOG.open('r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))

    names = [entry.get('event') for entry in events]
    assert any(e.get('event') == 'pandas.read_csv' and e.get('path') == str(TELEMETRY) for e in events), \
        'The script must load /home/user/telemetry.csv using pandas.'
    assert ('StandardScaler.fit_transform' in names or
            ('StandardScaler.fit' in names and 'StandardScaler.transform' in names)), \
        'The script must fit and apply StandardScaler.'
    assert any(e.get('event') == 'PCA.init' and e.get('n_components') == 5 and e.get('random_state') == 42 for e in events), \
        'PCA must be initialized with n_components=5 and random_state=42.'
    assert ('PCA.fit_transform' in names or ('PCA.fit' in names and 'PCA.transform' in names)), \
        'The script must fit and apply PCA.'
    assert 'PCA.inverse_transform' in names, 'The script must inverse-transform the PCA data.'
    assert any(e.get('event') == 'IsolationForest.init' and e.get('random_state') == 42 for e in events), \
        'IsolationForest must be initialized with random_state=42.'
    assert ('IsolationForest.fit_predict' in names or
            ('IsolationForest.fit' in names and 'IsolationForest.predict' in names)), \
        'The script must train IsolationForest and predict anomalies.'


def execute(script, frame, expected):
    frame.to_csv(TELEMETRY, index=False)
    METRICS.unlink(missing_ok=True)
    CALL_LOG.unlink(missing_ok=True)
    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/verifier_hooks' + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['PIPELINE_CALL_LOG'] = str(CALL_LOG)
    completed = subprocess.run(
        ['python3', str(script)], cwd=str(script.parent), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert completed.returncode == 0, \
        f"Script {script} failed with exit code {completed.returncode}:\n{completed.stderr[-2000:]}"
    load_and_assert_metrics(expected)
    assert_pipeline_calls()


def synthetic_frames():
    frames = []
    for seed, rows, noise in [(99173, 417, 0.03), (28411, 653, 0.35)]:
        rng = np.random.default_rng(seed)
        x = rng.normal(size=(rows, 50))
        x[:, 10:20] = 0.65 * x[:, 0:10] + rng.normal(scale=noise, size=(rows, 10))
        x[:, 20:25] += 0.4 * x[:, 25:30]
        x[:max(3, rows // 80), 35:45] += rng.normal(7.0, 0.5, size=(max(3, rows // 80), 10))
        frames.append(pd.DataFrame(x, columns=[f'feature_{i}' for i in range(50)]))
    return frames


def test_submitted_pipeline():
    assert TELEMETRY.is_file(), f'Required input {TELEMETRY} is missing.'
    original_bytes = TELEMETRY.read_bytes()
    original_frame = pd.read_csv(TELEMETRY)

    preferred = Path('/home/user/pipeline.py')
    candidates = []
    if preferred.is_file() and not preferred.is_symlink():
        candidates.append(preferred)
    candidates.extend(
        p for p in sorted(Path('/home/user').rglob('*.py'))
        if p.is_file() and not p.is_symlink() and p != preferred
    )
    assert candidates, 'No Python pipeline script was found under /home/user.'

    original_expected = {'reconstruction_mse': 0.8123, 'anomaly_count': 12}
    generated = synthetic_frames()
    generated_cases = [(frame, expected_metrics(frame)) for frame in generated]
    failures = []

    try:
        for script in candidates:
            try:
                # Exercise the artifact on the supplied input and retain the original assertions.
                execute(script, original_frame, original_expected)
                # Re-run on verifier-generated inputs to reject hardcoded metrics.
                for frame, expected in generated_cases:
                    execute(script, frame, expected)
                # Leave the requested output corresponding to the original telemetry.
                TELEMETRY.write_bytes(original_bytes)
                execute(script, original_frame, original_expected)
                return
            except Exception as exc:
                failures.append(f'{script}: {exc}')
                TELEMETRY.write_bytes(original_bytes)
    finally:
        TELEMETRY.write_bytes(original_bytes)

    raise AssertionError('No submitted Python script implemented the required pipeline:\n' + '\n'.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
