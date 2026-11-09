#!/bin/bash
set -e
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

SCRIPT=/home/user/run_pipeline.sh
[ -f "$SCRIPT" ] || fail
[ -x "$SCRIPT" ] || fail

# Force the submitted entrypoint to reproduce the environment and all outputs.
rm -rf /home/user/venv
rm -f /home/user/data.csv /home/user/metrics.json /home/user/residuals.png
if ! timeout 600 su -s /bin/bash user -c 'cd /home/user && /home/user/run_pipeline.sh'; then
    fail
fi

# Execute pipeline.py under instrumentation. This records the actual data passed
# to Ridge and the actual predictions/scatter coordinates, allowing pytest to
# recompute MAE rather than trusting metrics.json.
cat << 'CAPTURE_EOF' > /tmp/capture_pipeline.py
import json
import os
import runpy
import numpy as np

os.environ['MPLBACKEND'] = 'Agg'

from sklearn.linear_model import Ridge
import matplotlib.axes

captures = {'fits': [], 'predictions': [], 'scatters': []}
original_fit = Ridge.fit
original_predict = Ridge.predict
original_scatter = matplotlib.axes.Axes.scatter

def recording_fit(self, X, y, *args, **kwargs):
    a = np.asarray(X, dtype=float)
    if a.ndim == 2:
        captures['fits'].append({
            'shape': list(a.shape),
            'means': np.mean(a, axis=0).tolist(),
            'stds': np.std(a, axis=0).tolist(),
        })
    return original_fit(self, X, y, *args, **kwargs)

def recording_predict(self, X, *args, **kwargs):
    result = original_predict(self, X, *args, **kwargs)
    captures['predictions'].append(np.asarray(result, dtype=float).ravel().tolist())
    return result

def recording_scatter(self, x, y, *args, **kwargs):
    try:
        captures['scatters'].append({
            'x': np.asarray(x, dtype=float).ravel().tolist(),
            'y': np.asarray(y, dtype=float).ravel().tolist(),
        })
    except Exception:
        pass
    return original_scatter(self, x, y, *args, **kwargs)

Ridge.fit = recording_fit
Ridge.predict = recording_predict
matplotlib.axes.Axes.scatter = recording_scatter

try:
    runpy.run_path('/home/user/pipeline.py', run_name='__main__')
finally:
    with open('/tmp/pipeline_capture.json', 'w') as f:
        json.dump(captures, f)
CAPTURE_EOF

if ! timeout 180 env MPLBACKEND=Agg /home/user/venv/bin/python /tmp/capture_pipeline.py; then
    fail
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import math
import numpy as np
import pandas as pd
import matplotlib.image as mpimg
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error


def test_run_pipeline_script_exists_and_executable():
    """Check that run_pipeline.sh exists and is executable."""
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_venv_exists():
    """Check that the virtual environment was created."""
    venv_path = '/home/user/venv'
    assert os.path.isdir(venv_path), f"Virtual environment not found at {venv_path}."
    python_bin = os.path.join(venv_path, 'bin', 'python')
    assert os.path.isfile(python_bin) or os.path.isfile(os.path.join(venv_path, 'bin', 'python3')), "Python executable not found in venv."


def test_required_packages_installed_in_venv():
    import subprocess
    subprocess.run([
        '/home/user/venv/bin/python', '-c',
        'import numpy, pandas, sklearn, matplotlib'
    ], check=True, timeout=60)


def test_generated_data_is_from_unmodified_generator():
    df = pd.read_csv('/home/user/data.csv')
    assert list(df.columns) == ['pressure', 'friction', 'target']
    assert len(df) == 2000

    np.random.seed(42)
    x1 = np.random.uniform(10000, 50000, 2000)
    x2 = np.random.uniform(0.001, 0.005, 2000)
    y = 0.05 * x1 + 15000 * x2 + np.random.normal(0, 10, 2000)
    assert np.allclose(df['pressure'].to_numpy(), x1, rtol=0, atol=1e-10)
    assert np.allclose(df['friction'].to_numpy(), x2, rtol=0, atol=1e-12)
    assert np.allclose(df['target'].to_numpy(), y, rtol=0, atol=1e-10)


def _capture_and_expected():
    with open('/tmp/pipeline_capture.json') as f:
        capture = json.load(f)
    df = pd.read_csv('/home/user/data.csv')
    indices = np.arange(len(df))
    _, test_indices = train_test_split(indices, test_size=0.2, random_state=42)
    expected_y = df['target'].to_numpy()[test_indices]
    return capture, expected_y


def test_ridge_was_fit_on_scaled_features():
    """Verify Ridge actually received features on comparable numerical scales."""
    capture, _ = _capture_and_expected()
    suitable = []
    for fit in capture['fits']:
        if fit['shape'] == [1600, 2]:
            stds = np.asarray(fit['stds'], dtype=float)
            if np.all(np.isfinite(stds)) and np.all(stds > 0):
                suitable.append(float(np.max(stds) / np.min(stds)))
    assert suitable, 'pipeline.py did not fit Ridge on the expected training data.'
    assert min(suitable) < 100.0, 'Ridge received features with vastly different scales.'


def test_metrics_json():
    """Check metrics.json and independently recompute MAE from Ridge predictions."""
    metrics_path = '/home/user/metrics.json'
    assert os.path.isfile(metrics_path), f"{metrics_path} does not exist."

    with open(metrics_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{metrics_path} does not contain valid JSON."

    assert "mae" in data, f"'mae' key missing in {metrics_path}."
    assert isinstance(data["mae"], (int, float)) and not isinstance(data["mae"], bool), f"'mae' is not a number in {metrics_path}."
    assert math.isfinite(data['mae']) and data['mae'] >= 0, 'MAE must be a finite, non-negative value.'
    assert data["mae"] < 50.0, f"MAE is {data['mae']}, which is not less than 50.0."

    capture, expected_y = _capture_and_expected()
    prediction_sets = [np.asarray(p, dtype=float) for p in capture['predictions'] if len(p) == len(expected_y)]
    assert prediction_sets, 'No Ridge predictions for the test set were produced.'
    recomputed = [mean_absolute_error(expected_y, p) for p in prediction_sets]
    matching = [m for m in recomputed if math.isclose(float(data['mae']), float(m), rel_tol=1e-7, abs_tol=1e-7)]
    assert matching, f"Reported MAE {data['mae']} does not match MAE recomputed from Ridge predictions: {recomputed}."
    assert min(matching) < 50.0


def test_residuals_plot():
    """Check that residuals.png is a real plot of true values against predictions."""
    plot_path = '/home/user/residuals.png'
    assert os.path.isfile(plot_path), f"{plot_path} does not exist."

    file_size = os.path.getsize(plot_path)
    assert file_size > 5000, f"{plot_path} is too small ({file_size} bytes), indicating it might be blank."

    image = np.asarray(mpimg.imread(plot_path), dtype=float)
    assert image.ndim in (2, 3) and image.size > 0
    rgb = image[..., :3] if image.ndim == 3 else image
    assert float(np.std(rgb)) > 0.01, 'residuals.png has insufficient visual variation.'
    assert float(np.mean(rgb < 0.98)) > 0.005, 'residuals.png is effectively a white canvas.'

    capture, expected_y = _capture_and_expected()
    predictions = [np.asarray(p, dtype=float) for p in capture['predictions'] if len(p) == len(expected_y)]
    found = False
    for scatter in capture['scatters']:
        x = np.asarray(scatter['x'], dtype=float)
        y = np.asarray(scatter['y'], dtype=float)
        if len(x) != len(expected_y) or not np.allclose(x, expected_y):
            continue
        if any(np.allclose(y, p) for p in predictions):
            found = True
            break
    assert found, 'The saved plotting run did not scatter true test values against Ridge predictions.'


def test_generate_data_unmodified():
    """Check that generate_data.py was not modified."""
    gen_path = '/home/user/generate_data.py'
    assert os.path.isfile(gen_path), f"{gen_path} does not exist."

    original_content = """import numpy as np
import pandas as pd

def generate():
    np.random.seed(42)
    n_samples = 2000

    # Feature 1: Very large scale (e.g., pressure in Pascals)
    X1 = np.random.uniform(10000, 50000, n_samples)

    # Feature 2: Very small scale (e.g., friction coefficient)
    X2 = np.random.uniform(0.001, 0.005, n_samples)

    # Target variable
    y = 0.05 * X1 + 15000 * X2 + np.random.normal(0, 10, n_samples)

    df = pd.DataFrame({'pressure': X1, 'friction': X2, 'target': y})
    df.to_csv('/home/user/data.csv', index=False)
    print("Data generated at /home/user/data.csv")

if __name__ == "__main__":
    generate()
"""
    with open(gen_path, 'r') as f:
        current_content = f.read()

    assert current_content == original_content, f"{gen_path} was modified."
TEST_EOF

if /home/user/venv/bin/python -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
