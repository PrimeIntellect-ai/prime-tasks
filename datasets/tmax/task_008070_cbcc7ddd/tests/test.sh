#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import json
import random
import pytest
import subprocess
import numpy as np
import pandas as pd
from pandas.api.types import is_float_dtype, is_integer_dtype


def run_python(script: str) -> str:
    """Helper to run a Python script in a subprocess and return its stdout."""
    res = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Script failed: {res.stderr}")
    return res.stdout.strip()


def test_phase1_parquet_exists_and_valid():
    """Verify that the cleaned dataset is saved as a Parquet file and respects schema constraints."""
    parquet_path = '/home/user/astro_data/clean_data.parquet'
    assert os.path.exists(parquet_path), f"Parquet file missing: {parquet_path}"

    script = f"""
import pandas as pd
try:
    df = pd.read_parquet('{parquet_path}')
    print(len(df))
    print((df['mass'] > 0).all())
    print((df['radius'].astype(float) > 0).all())
    print(df['status'].isin(['confirmed', 'false_positive']).all())
except Exception as e:
    print(f"ERROR: {{e}}")
"""
    output = run_python(script).splitlines()
    assert not output[0].startswith("ERROR"), f"Failed to read parquet file: {output[0]}"
    assert len(output) >= 4, "Unexpected output from validation script"

    assert output[0] == "4956", f"Expected 4956 valid rows after dropping invalid ones, got {output[0]}"
    assert output[1] == "True", "Found rows with mass <= 0"
    assert output[2] == "True", "Found rows with radius <= 0"
    assert output[3] == "True", "Found rows with invalid status"

    # Reconstruct the originally supplied CSV independently, and ensure the raw
    # input itself was not replaced before deriving the expected cleaned rows.
    np.random.seed(10)
    random.seed(10)
    n_rows = 5000
    source = pd.DataFrame({
        'id': list(range(1, n_rows + 1)),
        'mass': np.random.lognormal(mean=1.0, sigma=0.5, size=n_rows),
        'orbital_period': np.random.uniform(1, 300, size=n_rows),
        'status': np.random.choice(['confirmed', 'false_positive'], size=n_rows, p=[0.4, 0.6])
    })
    radii = source['mass'].to_numpy() * 1.5 + np.random.normal(0, 0.5, size=n_rows)
    source['radius'] = np.where(radii < 0.1, 0.1, radii)
    source = source[['id', 'mass', 'radius', 'orbital_period', 'status']]
    source.loc[10:20, 'mass'] = -1.0
    source.loc[30:40, 'radius'] = 'unknown'
    source.loc[50:60, 'status'] = 'candidate'
    source.loc[70:80, 'orbital_period'] = -10.5

    csv_buffer = io.StringIO()
    source.to_csv(csv_buffer, index=False)
    canonical_raw = pd.read_csv(io.StringIO(csv_buffer.getvalue()))
    raw = pd.read_csv('/home/user/astro_data/raw_candidates.csv')
    pd.testing.assert_frame_equal(raw, canonical_raw, check_dtype=True, check_exact=True)

    id_values = pd.to_numeric(raw['id'], errors='coerce')
    mass_values = pd.to_numeric(raw['mass'], errors='coerce')
    radius_values = pd.to_numeric(raw['radius'], errors='coerce')
    period_values = pd.to_numeric(raw['orbital_period'], errors='coerce')

    valid = (
        id_values.notna()
        & np.isfinite(id_values)
        & id_values.eq(np.floor(id_values))
        & mass_values.notna()
        & np.isfinite(mass_values)
        & mass_values.gt(0)
        & radius_values.notna()
        & np.isfinite(radius_values)
        & radius_values.gt(0)
        & period_values.notna()
        & np.isfinite(period_values)
        & period_values.gt(0)
        & raw['status'].isin(['confirmed', 'false_positive'])
    )

    expected = raw.loc[valid].copy()
    expected['id'] = id_values.loc[valid].astype('int64')
    expected['mass'] = mass_values.loc[valid].astype(float)
    expected['radius'] = radius_values.loc[valid].astype(float)
    expected['orbital_period'] = period_values.loc[valid].astype(float)
    expected = expected.reset_index(drop=True)

    actual = pd.read_parquet(parquet_path)
    assert list(actual.columns) == list(expected.columns), "Cleaned Parquet columns do not match the raw dataset"
    assert is_integer_dtype(actual['id'].dtype), "id must have an integer dtype"
    assert is_float_dtype(actual['mass'].dtype), "mass must have a float dtype"
    assert is_float_dtype(actual['radius'].dtype), "radius must have a float dtype"
    assert is_float_dtype(actual['orbital_period'].dtype), "orbital_period must have a float dtype"
    assert (actual['orbital_period'] > 0).all(), "Found rows with orbital_period <= 0"

    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-7,
        atol=1e-9,
    )


def test_phase2_bootstrap_ci():
    """Verify the bootstrap confidence interval was computed correctly and saved properly."""
    ci_path = '/home/user/astro_data/bootstrap_ci.txt'
    assert os.path.exists(ci_path), f"Bootstrap CI file missing: {ci_path}"

    script = """
import pandas as pd
import numpy as np
df = pd.read_parquet('/home/user/astro_data/clean_data.parquet')
df_conf = df[df['status'] == 'confirmed']
radii_conf = df_conf['radius'].astype(float).values
np.random.seed(42)
means = [np.mean(np.random.choice(radii_conf, size=len(radii_conf), replace=True)) for _ in range(1000)]
print(f"{np.percentile(means, 2.5):.4f},{np.percentile(means, 97.5):.4f}")
"""
    expected_ci = run_python(script)
    exp_lower, exp_upper = map(float, expected_ci.split(','))

    with open(ci_path, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, f"Bootstrap CI file must contain exactly two comma-separated values, got: {content}"

    try:
        act_lower, act_upper = map(float, parts)
    except ValueError:
        pytest.fail(f"Could not parse floats from bootstrap_ci.txt: {content}")

    assert abs(act_lower - exp_lower) < 1e-3, f"Expected lower CI bound ~{exp_lower}, got {act_lower}"
    assert abs(act_upper - exp_upper) < 1e-3, f"Expected upper CI bound ~{exp_upper}, got {act_upper}"


def test_phase3_metrics():
    """Verify the model evaluation metrics are computed correctly and saved as JSON."""
    metrics_path = '/home/user/astro_data/metrics.json'
    assert os.path.exists(metrics_path), f"Metrics file missing: {metrics_path}"

    script = """
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score

df = pd.read_parquet('/home/user/astro_data/clean_data.parquet')

df_conf = df[df['status'] == 'confirmed']
X_reg = df_conf[['mass', 'orbital_period']].values
y_reg = df_conf['radius'].values
rf = RandomForestRegressor(random_state=42)
mse_scores = cross_val_score(rf, X_reg, y_reg, cv=5, scoring='neg_mean_squared_error')
rmse = np.sqrt(np.mean(-mse_scores))

X_clf = df[['mass', 'radius', 'orbital_period']].values
y_clf = df['status'].values
lr = LogisticRegression(random_state=42)
f1_scores = cross_val_score(lr, X_clf, y_clf, cv=5, scoring='f1_macro')
f1 = np.mean(f1_scores)

print(f"{rmse:.4f},{f1:.4f}")
"""
    expected_metrics = run_python(script)
    exp_rmse, exp_f1 = map(float, expected_metrics.split(','))

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("metrics.json is not valid JSON")

    assert "rmse" in metrics, "Missing 'rmse' key in metrics.json"
    assert "f1" in metrics, "Missing 'f1' key in metrics.json"
    assert isinstance(metrics["rmse"], (int, float)), "rmse must be a number"
    assert isinstance(metrics["f1"], (int, float)), "f1 must be a number"
    assert abs(metrics["rmse"] - exp_rmse) < 1e-3, f"Expected RMSE ~{exp_rmse}, got {metrics['rmse']}"
    assert abs(metrics["f1"] - exp_f1) < 1e-3, f"Expected F1 ~{exp_f1}, got {metrics['f1']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
