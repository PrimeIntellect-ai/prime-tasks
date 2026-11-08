#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import pandas as pd
import numpy as np
from PIL import Image


def test_oracle_used_only_to_label_training_data():
    log_path = '/var/log/oracle_calls.log'
    train_path = '/home/user/train.csv'

    assert os.path.exists(log_path), 'Oracle audit log is missing'
    train_df = pd.read_csv(train_path)
    expected = {
        (round(float(a), 8), round(float(b), 8))
        for a, b in zip(train_df['featureA'], train_df['featureB'])
    }

    observed = set()
    with open(log_path, encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split(',')
            assert len(parts) == 2, 'Malformed oracle audit entry'
            try:
                a, b = map(float, parts)
            except ValueError:
                raise AssertionError('Malformed oracle audit entry')
            assert np.isfinite(a) and np.isfinite(b), 'Oracle was called with non-finite inputs'
            key = (round(a, 8), round(b, 8))
            assert key in expected, (
                'The oracle was called on data outside train.csv; test predictions must be '
                'produced by the surrogate rather than direct oracle calls'
            )
            observed.add(key)

    missing = expected - observed
    assert not missing, f'{len(missing)} training rows were not labeled with the oracle'


def test_predictions_mse():
    preds_path = '/home/user/predictions.csv'
    test_path = '/home/user/test.csv'

    assert os.path.exists(preds_path), f'Predictions file not found at {preds_path}'

    test_df = pd.read_csv(test_path)
    preds_df = pd.read_csv(preds_path)

    assert 'id' in preds_df.columns, "Predictions missing 'id' column"
    assert 'prediction' in preds_df.columns, "Predictions missing 'prediction' column"
    assert list(preds_df.columns) == ['id', 'prediction'], \
        "Predictions must contain exactly the columns 'id' and 'prediction'"
    assert len(preds_df) == len(test_df), 'Predictions must contain exactly one row per test ID'
    assert preds_df['id'].is_unique, 'Prediction IDs must be unique'

    # Compute true values
    true_vals = np.sin(test_df['featureA']) * 2.0 + np.cos(test_df['featureB']) * 3.0 + test_df['featureA'] * test_df['featureB']

    # Merge to align IDs
    merged = pd.merge(test_df[['id']], preds_df, on='id', how='left')

    assert not merged['prediction'].isna().any(), 'Predictions contain missing values for some IDs'
    assert np.isfinite(merged['prediction']).all(), 'Predictions contain non-finite values'

    mse = np.mean((merged['prediction'] - true_vals)**2)

    assert mse < 0.05, f'MSE is {mse:.5f}, which is not < 0.05'


def test_plot_png_not_blank():
    script_path = '/home/user/plot_data.py'
    plot_path = '/home/user/plot.png'
    assert os.path.isfile(script_path), f'Plot script not found at {script_path}'

    with open(script_path, encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=script_path)
    call_names = {
        node.func.attr if isinstance(node.func, ast.Attribute)
        else node.func.id if isinstance(node.func, ast.Name)
        else None
        for node in ast.walk(tree) if isinstance(node, ast.Call)
    }
    constants = {node.value for node in ast.walk(tree) if isinstance(node, ast.Constant)}
    assert 'featureC' in constants, 'plot_data.py does not select featureC'
    assert 'hist' in call_names, 'plot_data.py does not create a histogram'
    assert 'savefig' in call_names, 'plot_data.py does not save the generated figure'

    if os.path.exists(plot_path):
        os.remove(plot_path)
    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', script_path], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f'plot_data.py failed: {result.stderr}'
    assert os.path.exists(plot_path), f'Plot not found at {plot_path}'

    img = Image.open(plot_path).convert('RGB')
    extrema = img.getextrema()

    # extrema is a tuple of (min, max) for each band: ((Rmin, Rmax), (Gmin, Gmax), (Bmin, Bmax))
    # If min == max for all bands, the image is a single solid color (i.e. blank)
    is_solid = all(vmin == vmax for vmin, vmax in extrema)
    assert not is_solid, 'The plot image appears to be completely blank (solid color). The plot script is likely still clearing the figure before saving.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
