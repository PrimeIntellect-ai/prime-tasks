#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.datasets import make_regression
from sklearn.decomposition import PCA
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.preprocessing import StandardScaler

HOME = Path('/home/user')
DATA = HOME / 'sensor_data.csv'
N_COMPONENTS = HOME / 'n_components.txt'
PCA_ERROR = HOME / 'pca_max_error.txt'
MSE = HOME / 'mse.txt'
OUTPUTS = (N_COMPONENTS, PCA_ERROR, MSE)


def reference_from_frame(df):
    expected_columns = [f'f{i}' for i in range(50)] + ['target']
    assert list(df.columns) == expected_columns, 'Unexpected dataset columns.'

    X = df[[f'f{i}' for i in range(50)]].to_numpy()
    y = df['target'].to_numpy()
    X_scaled = StandardScaler().fit_transform(X)

    pca = PCA(random_state=42)
    transformed = pca.fit_transform(X_scaled)
    cumulative = np.cumsum(pca.explained_variance_ratio_)
    k = int(np.searchsorted(cumulative, 0.95, side='left') + 1)

    reconstructed = pca.inverse_transform(transformed)
    max_error = float(np.max(np.abs(X_scaled - reconstructed)))

    model = Ridge(alpha=1.0)
    model.fit(transformed[:, :k], y)
    mse = float(mean_squared_error(y, model.predict(transformed[:, :k])))
    return k, max_error, mse


def validate_outputs(reference, require_original_k=False):
    expected_k, expected_error, expected_mse = reference

    assert N_COMPONENTS.exists(), f'File {N_COMPONENTS} does not exist.'
    content = N_COMPONENTS.read_text().strip()
    assert content.isdigit(), f"Expected an integer in {N_COMPONENTS}, got '{content}'."
    if require_original_k:
        assert content == '46', f'Expected k to be 46 for this dataset, but got {content}.'
    assert int(content) == expected_k, f'Expected recomputed k={expected_k}, got {content}.'

    assert PCA_ERROR.exists(), f'File {PCA_ERROR} does not exist.'
    error_text = PCA_ERROR.read_text().strip()
    try:
        error_value = float(error_text)
    except ValueError as exc:
        raise AssertionError(f"Could not parse {PCA_ERROR} as a float: '{error_text}'.") from exc
    assert 'e' in error_text.lower(), f"Expected scientific notation in {PCA_ERROR}, got '{error_text}'."
    assert math.isfinite(error_value) and error_value >= 0
    assert error_value < 1e-12, f'Expected max reconstruction error below 1e-12, got {error_value}.'
    assert expected_error > 0
    assert math.isclose(error_value, expected_error, rel_tol=5e-3, abs_tol=1e-18), (
        f'Expected recomputed PCA error {expected_error:e}, got {error_value:e}.'
    )

    assert MSE.exists(), f'File {MSE} does not exist.'
    mse_text = MSE.read_text().strip()
    assert re.fullmatch(r'[+-]?\d+\.\d{4}', mse_text), (
        f"Expected MSE rounded to exactly 4 decimal places, got '{mse_text}'."
    )
    mse_value = float(mse_text)
    assert math.isfinite(mse_value)
    expected_text = f'{expected_mse:.4f}'
    assert mse_text == expected_text, f'Expected recomputed MSE {expected_text}, got {mse_text}.'


# Ensure the supplied input was not replaced, then validate the initially submitted outputs.
original_df = pd.read_csv(DATA)
canonical_X, canonical_y = make_regression(
    n_samples=1000, n_features=50, n_informative=10, noise=0.1, random_state=42
)
canonical = np.column_stack((canonical_X, canonical_y))
assert original_df.shape == canonical.shape
assert np.allclose(original_df.to_numpy(), canonical, rtol=0, atol=1e-12), 'sensor_data.csv was modified.'
original_reference = reference_from_frame(original_df)
validate_outputs(original_reference, require_original_k=True)

# The instruction requires a Python script. Re-execute a submitted script on an
# unpredictable dataset and derive the expected answers independently.
candidates = []
for root, dirs, files in os.walk(HOME):
    dirs[:] = [d for d in dirs if d != '__pycache__' and not d.startswith('.')]
    for name in files:
        if name.endswith('.py'):
            candidates.append(Path(root) / name)
assert candidates, 'No Python script was found under /home/user.'

saved_data = DATA.read_bytes()
saved_outputs = {path: path.read_bytes() for path in OUTPUTS}
passed = False
failures = []
try:
    seed = secrets.randbits(32)
    X, y = make_regression(
        n_samples=321, n_features=50, n_informative=13,
        noise=0.37, random_state=seed
    )
    dynamic_df = pd.DataFrame(X, columns=[f'f{i}' for i in range(50)])
    dynamic_df['target'] = y
    dynamic_reference = reference_from_frame(dynamic_df)
    dynamic_csv = dynamic_df.to_csv(index=False).encode()

    for candidate in candidates:
        DATA.write_bytes(dynamic_csv)
        for path in OUTPUTS:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        try:
            result = subprocess.run(
                ['runuser', '-u', 'user', '--', 'python3', str(candidate)],
                cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=60
            )
            assert result.returncode == 0, result.stderr[-1000:]
            assert DATA.read_bytes() == dynamic_csv, 'The script modified its input dataset.'
            validate_outputs(dynamic_reference)
            passed = True
            break
        except Exception as exc:
            failures.append(f'{candidate}: {exc}')

    assert passed, 'No submitted Python script produced correct recomputed outputs. ' + ' | '.join(failures[-5:])
finally:
    DATA.write_bytes(saved_data)
    for path, content in saved_outputs.items():
        path.write_bytes(content)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
