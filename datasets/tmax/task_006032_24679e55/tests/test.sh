#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "h5py:h5py"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import sys
import tempfile

import h5py
import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

PIPELINE = '/home/user/pipeline.py'
PARQUET = '/home/user/anomalies.parquet'
HDF5 = '/home/user/model_data.h5'
FEATURES = ['amount', 'duration', 'location_score', 'network_latency', 'device_trust']
ORIGINAL_COLUMNS = ['transaction_id'] + FEATURES
EXPECTED_COLUMNS = ORIGINAL_COLUMNS + ['pc1', 'pc2', 'pc3']


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline():
    assert os.path.isfile(PIPELINE), 'The file /home/user/pipeline.py was not created.'
    assert not os.path.islink(PIPELINE), '/home/user/pipeline.py must be a regular script, not a symbolic link.'
    assert stat.S_ISREG(os.stat(PIPELINE).st_mode), '/home/user/pipeline.py is not a regular file.'

    for path in (PARQUET, HDF5):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        result = subprocess.run(
            [sys.executable, PIPELINE],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=300,
            cwd='/home/user',
        )
    except subprocess.TimeoutExpired:
        pytest.fail('pipeline.py did not finish within 300 seconds.')

    assert result.returncode == 0, f'pipeline.py failed with exit code {result.returncode}:\n{result.stdout}'


@pytest.fixture(scope='session')
def reference():
    # Independently recreate the immutable dataset produced by setup, including
    # the CSV serialization/read round trip used by the requested pipeline.
    np.random.seed(123)
    n_samples = 10000
    data = {
        'transaction_id': [f'TXN_{i:05d}' for i in range(n_samples)],
        'amount': np.random.exponential(scale=100, size=n_samples),
        'duration': np.random.normal(loc=50, scale=10, size=n_samples),
        'location_score': np.random.uniform(0, 100, size=n_samples),
        'network_latency': np.random.lognormal(mean=2, sigma=0.5, size=n_samples),
        'device_trust': np.random.beta(a=5, b=2, size=n_samples) * 100,
    }
    anomaly_indices = np.random.choice(n_samples, size=300, replace=False)
    data['amount'][anomaly_indices] *= 10
    data['network_latency'][anomaly_indices] *= 5

    generated = pd.DataFrame(data)
    with tempfile.NamedTemporaryFile(suffix='.csv') as tmp:
        generated.to_csv(tmp.name, index=False)
        raw = pd.read_csv(tmp.name)

    standardized = StandardScaler().fit_transform(raw[FEATURES])
    pca = PCA(n_components=3, random_state=42)
    pcs = pca.fit_transform(standardized)
    return raw, pcs, pca.components_


def read_and_validate_components(reference_components):
    with h5py.File(HDF5, 'r') as f:
        assert 'pca_components' in f, "HDF5 file does not contain dataset 'pca_components'."
        actual = f['pca_components'][:]

    expected_shape = [3, 5]
    actual_shape = list(actual.shape)
    assert actual_shape == expected_shape, f'Expected PCA components shape {expected_shape}, but got {actual_shape}.'
    assert np.isfinite(actual).all(), 'PCA components contain non-finite values.'

    # Principal axes may be represented with either sign. Determine each sign
    # from the submitted axes and require the corresponding PC values to use it.
    signs = np.where(np.sum(actual * reference_components, axis=1) >= 0, 1.0, -1.0)
    np.testing.assert_allclose(
        actual,
        reference_components * signs[:, None],
        rtol=1e-7,
        atol=1e-8,
        err_msg='pca_components does not contain the PCA axes computed from the five standardized features.',
    )
    return signs


def test_output_files_exist():
    assert os.path.isfile(PARQUET), 'The file /home/user/anomalies.parquet was not created.'
    assert os.path.isfile(HDF5), 'The file /home/user/model_data.h5 was not created.'


def test_parquet_contents(reference):
    raw, reference_pcs, reference_components = reference
    try:
        actual = pd.read_parquet(PARQUET)
    except Exception as exc:
        pytest.fail(f'Error reading parquet file: {exc}')

    # Preserve the original structural assertions.
    assert len(actual) == 500, f'Expected exactly 500 anomalous records, but found {len(actual)}.'
    expected_column_set = set(EXPECTED_COLUMNS)
    missing_columns = expected_column_set - set(actual.columns)
    assert not missing_columns, f'Missing columns in Parquet file: {missing_columns}. Found: {set(actual.columns)}'

    signs = read_and_validate_components(reference_components)
    signed_pcs = reference_pcs * signs
    model = IsolationForest(contamination=0.05, random_state=42)
    predictions = model.fit_predict(signed_pcs)
    expected_mask = predictions == -1
    assert int(expected_mask.sum()) == 500

    expected = raw.loc[expected_mask, ORIGINAL_COLUMNS].copy()
    expected[['pc1', 'pc2', 'pc3']] = signed_pcs[expected_mask]

    assert actual['transaction_id'].notna().all(), 'Anomaly output contains missing transaction IDs.'
    assert actual['transaction_id'].is_unique, 'Anomaly output contains duplicate transaction IDs.'
    assert set(actual['transaction_id']) == set(expected['transaction_id']), \
        'The Parquet file does not contain the anomalies predicted by the required IsolationForest pipeline.'

    actual_by_id = actual[EXPECTED_COLUMNS].set_index('transaction_id').sort_index()
    expected_by_id = expected[EXPECTED_COLUMNS].set_index('transaction_id').sort_index()

    for column in FEATURES + ['pc1', 'pc2', 'pc3']:
        actual_values = pd.to_numeric(actual_by_id[column], errors='coerce').to_numpy()
        expected_values = expected_by_id[column].to_numpy()
        assert np.isfinite(actual_values).all(), f'Column {column} contains non-finite or non-numeric values.'
        np.testing.assert_allclose(
            actual_values,
            expected_values,
            rtol=1e-7,
            atol=1e-8,
            err_msg=f'Column {column} does not match the recomputed pipeline result.',
        )


def test_hdf5_contents(reference):
    _, _, reference_components = reference
    read_and_validate_components(reference_components)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
