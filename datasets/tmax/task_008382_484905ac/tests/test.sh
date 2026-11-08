#!/bin/bash
mkdir -p /logs/verifier

cat << 'PRECHECK_EOF' > /tmp/check_etl_pipeline.py
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error

SCRIPT = '/home/user/etl_pipeline.py'
DATA = '/home/user/data/sensor_readings.csv'
METRICS = '/home/user/metrics.json'


def expected_metrics(path):
    df = pd.read_csv(path)
    sensor_cols = ['s1', 's2', 's3', 's4', 's5']

    for col in sensor_cols:
        df[col] = df[col].fillna(df[col].median())

    for col in sensor_cols:
        lower = df[col].quantile(0.05)
        upper = df[col].quantile(0.95)
        df[col] = df[col].clip(lower=lower, upper=upper)

    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df['hour'] = df['timestamp'].dt.hour

    pca = PCA(n_components=2, svd_solver='full')
    components = pca.fit_transform(df[sensor_cols])
    df['pca1'] = components[:, 0]
    df['pca2'] = components[:, 1]

    X = df[['hour', 'pca1', 'pca2']]
    y = df['target']
    model = LinearRegression()
    model.fit(X, y)
    predictions = model.predict(X)

    mse = mean_squared_error(y, predictions)
    np.random.seed(42)
    n = len(df)
    y_values = y.values
    bootstrap_mses = []
    for _ in range(1000):
        indices = np.random.choice(n, n, replace=True)
        bootstrap_mses.append(
            mean_squared_error(y_values[indices], predictions[indices])
        )

    return {
        'mse': mse,
        'mse_ci_lower': np.percentile(bootstrap_mses, 2.5),
        'mse_ci_upper': np.percentile(bootstrap_mses, 97.5),
    }


def run_submission():
    if os.path.lexists(METRICS):
        if not os.path.isfile(METRICS):
            raise AssertionError(f'{METRICS} exists but is not a file')
        os.unlink(METRICS)

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        raise AssertionError(
            'etl_pipeline.py failed when executed.\n'
            f'stdout:\n{result.stdout}\n'
            f'stderr:\n{result.stderr}'
        )
    if not os.path.isfile(METRICS):
        raise AssertionError('etl_pipeline.py did not generate /home/user/metrics.json')


def validate_metrics(expected):
    try:
        with open(METRICS, 'r') as handle:
            actual = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError('etl_pipeline.py generated invalid JSON') from exc

    for key in ('mse', 'mse_ci_lower', 'mse_ci_upper'):
        if key not in actual:
            raise AssertionError(f"Generated metrics are missing key '{key}'")
        if not isinstance(actual[key], (int, float)):
            raise AssertionError(f"Generated value for '{key}' is not numeric")
        relative_error = (
            abs(actual[key] - expected[key]) / abs(expected[key])
            if expected[key] != 0
            else abs(actual[key])
        )
        if relative_error > 0.01:
            raise AssertionError(
                f"etl_pipeline.py produced an incorrect {key} on the verification dataset: "
                f"actual={actual[key]}, expected={expected[key]}"
            )


if not os.path.exists(SCRIPT):
    raise AssertionError('/home/user/etl_pipeline.py does not exist')
script_info = os.lstat(SCRIPT)
if not stat.S_ISREG(script_info.st_mode):
    raise AssertionError('/home/user/etl_pipeline.py is not a regular file')
if script_info.st_size == 0:
    raise AssertionError('/home/user/etl_pipeline.py is empty')

backup_handle = tempfile.NamedTemporaryFile(prefix='sensor_readings_', suffix='.csv', delete=False)
backup_path = backup_handle.name
backup_handle.close()
shutil.copy2(DATA, backup_path)

try:
    # Exercise the submitted script on a second, deterministic dataset so a script
    # which merely emits metrics prepared for the original CSV cannot pass.
    original = pd.read_csv(backup_path)
    alternate = original.iloc[::7].reset_index(drop=True)
    alternate['timestamp'] = (
        pd.to_datetime(alternate['timestamp']) + pd.Timedelta(hours=5)
    ).dt.strftime('%Y-%m-%d %H:%M:%S')
    alternate['s1'] = alternate['s1'] * 1.7 + np.sin(np.arange(len(alternate)) / 9.0)
    alternate['s2'] = alternate['s2'] * -0.8 + 3.0
    alternate['s3'] = alternate['s3'] ** 2
    alternate['s4'] = alternate['s4'] * 0.35 - 8.0
    alternate['s5'] = alternate['s5'] + np.cos(np.arange(len(alternate)) / 11.0) * 4.0
    alternate['target'] = alternate['target'] * 1.13 + (np.arange(len(alternate)) % 17) ** 2 * 0.04
    alternate.loc[alternate.index[::31], 's1'] = np.nan
    alternate.loc[alternate.index[::37], 's4'] = np.nan
    alternate.loc[alternate.index[5::113], 's2'] = 5000.0
    alternate.loc[alternate.index[9::127], 's5'] = -4000.0
    alternate.to_csv(DATA, index=False)

    try:
        expected = expected_metrics(DATA)
        run_submission()
        validate_metrics(expected)
    finally:
        shutil.copy2(backup_path, DATA)

    # Run the required artifact against the original dataset and leave its output
    # in place for the original verifier assertions below.
    try:
        run_submission()
    finally:
        shutil.copy2(backup_path, DATA)
finally:
    if os.path.exists(backup_path):
        os.unlink(backup_path)
PRECHECK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import subprocess
import sys

def get_expected_metrics():
    """
    Computes the expected metrics using the canonical solution.
    We run this in a subprocess to strictly adhere to the rule of using only standard
    library imports in the test file itself, while leveraging the environment's packages.
    """
    script = """
import pandas as pd
import numpy as np
import json
from sklearn.decomposition import PCA
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error

df = pd.read_csv('/home/user/data/sensor_readings.csv')
sensor_cols = ['s1', 's2', 's3', 's4', 's5']

# 1. Impute median
for col in sensor_cols:
    df[col] = df[col].fillna(df[col].median())

# 2. Clip at 5th and 95th percentiles
for col in sensor_cols:
    lower = df[col].quantile(0.05)
    upper = df[col].quantile(0.95)
    df[col] = df[col].clip(lower=lower, upper=upper)

# 3. Feature engineering
df['timestamp'] = pd.to_datetime(df['timestamp'])
df['hour'] = df['timestamp'].dt.hour

# 4. PCA
pca = PCA(n_components=2, svd_solver='full')
pca_features = pca.fit_transform(df[sensor_cols])
df['pca1'] = pca_features[:, 0]
df['pca2'] = pca_features[:, 1]

# 5. Model Training
X = df[['hour', 'pca1', 'pca2']]
y = df['target']
model = LinearRegression()
model.fit(X, y)
preds = model.predict(X)

# 6. Evaluation & Bootstrapping
mse = mean_squared_error(y, preds)

np.random.seed(42)
n = len(df)
bootstrap_mses = []
y_arr = y.values
preds_arr = preds

for _ in range(1000):
    indices = np.random.choice(n, n, replace=True)
    b_y = y_arr[indices]
    b_preds = preds_arr[indices]
    bootstrap_mses.append(mean_squared_error(b_y, b_preds))

ci_lower = np.percentile(bootstrap_mses, 2.5)
ci_upper = np.percentile(bootstrap_mses, 97.5)

expected = {
    "mse": mse,
    "mse_ci_lower": ci_lower,
    "mse_ci_upper": ci_upper
}
print(json.dumps(expected))
"""
    try:
        result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected metrics. Subprocess error: {e.stderr}")

def test_metrics_json_exists():
    assert os.path.exists('/home/user/metrics.json'), "/home/user/metrics.json does not exist. The script must output the results to this exact path."
    assert os.path.isfile('/home/user/metrics.json'), "/home/user/metrics.json exists but is not a file."

def test_metrics_values():
    metrics_path = '/home/user/metrics.json'
    assert os.path.exists(metrics_path), "Cannot validate values because /home/user/metrics.json is missing."

    with open(metrics_path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/metrics.json is not valid JSON.")

    expected = get_expected_metrics()

    required_keys = ["mse", "mse_ci_lower", "mse_ci_upper"]
    for key in required_keys:
        assert key in actual, f"Key '{key}' is missing from the JSON output."

        act_val = actual[key]
        exp_val = expected[key]

        assert isinstance(act_val, (int, float)), f"Value for '{key}' must be a float, got {type(act_val).__name__}."

        rel_error = abs(act_val - exp_val) / abs(exp_val) if exp_val != 0 else abs(act_val)
        assert rel_error <= 0.01, (
            f"Value for '{key}' is incorrect.\n"
            f"Actual: {act_val}\n"
            f"Expected: ~{exp_val}\n"
            f"Relative Error: {rel_error:.4f} (Must be <= 0.01)"
        )
TEST_EOF

if python3 /tmp/check_etl_pipeline.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
