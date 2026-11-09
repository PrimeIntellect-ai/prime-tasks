#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import tempfile

import cv2
import numpy as np
import pandas as pd
import pytest
from sklearn.metrics import mean_squared_error

CPP_PATH = '/home/user/pipeline.cpp'
CSV_PATH = '/home/user/predictions.csv'
JSON_PATH = '/home/user/model_artifacts.json'
VIDEO_PATH = '/app/reaction.mp4'


def reference_results():
    cap = cv2.VideoCapture(VIDEO_PATH)
    rgb = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        # OpenCV decodes BGR; the required features are RGB.
        bgr = frame.mean(axis=(0, 1))
        rgb.append([bgr[2], bgr[1], bgr[0]])
    cap.release()

    assert rgb, 'No frames could be decoded from reaction.mp4'
    x = np.asarray(rgb, dtype=float)
    means = x.mean(axis=0)
    stds = x.std(axis=0, ddof=1)
    assert np.all(stds > 0), 'Video contains a constant RGB feature'
    z = (x - means) / stds
    covariance = np.cov(z, rowvar=False, ddof=1)
    values, vectors = np.linalg.eigh(covariance)
    eigenvector = vectors[:, np.argmax(values)]
    eigenvector /= np.linalg.norm(eigenvector)

    p = z @ eigenvector
    y = np.arange(len(x), dtype=float)
    slope = np.sum((p - p.mean()) * (y - y.mean())) / np.sum((p - p.mean()) ** 2)
    intercept = y.mean() - slope * p.mean()
    predictions = slope * p + intercept
    mse = float(np.mean((y - predictions) ** 2))
    return y, eigenvector, float(slope), float(intercept), predictions, mse


@pytest.fixture(scope='session', autouse=True)
def compile_and_execute_pipeline():
    assert os.path.exists(CPP_PATH), f'File not found: {CPP_PATH}'
    assert os.path.isfile(CPP_PATH), f'Not a regular file: {CPP_PATH}'
    assert os.path.getsize(CPP_PATH) > 0, f'Empty C++ source: {CPP_PATH}'

    # Outputs must be produced by a freshly compiled execution of the submitted source.
    for path in (CSV_PATH, JSON_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build_dir = tempfile.mkdtemp(prefix='pipeline-verifier-')
    executable = os.path.join(build_dir, 'pipeline')
    try:
        subprocess.run(
            ['g++', '-std=c++17', '-O2', CPP_PATH, '-o', executable],
            check=True, timeout=120, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True
        )
        subprocess.run(
            [executable], cwd='/home/user', check=True, timeout=120,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f'Compilation or execution failed: {exc.stderr or exc.stdout}')
    except subprocess.TimeoutExpired:
        pytest.fail('Compilation or execution timed out')
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_predictions_csv_and_mse():
    """Verify fresh predictions cover every real video frame and are accurate."""
    assert os.path.exists(CSV_PATH), f'File not found: {CSV_PATH}'
    try:
        df = pd.read_csv(CSV_PATH)
    except Exception as exc:
        pytest.fail(f'Failed to read {CSV_PATH} as CSV: {exc}')

    assert 'true_index' in df.columns, "Column 'true_index' missing from predictions.csv"
    assert 'predicted_index' in df.columns, "Column 'predicted_index' missing from predictions.csv"
    assert list(df.columns) == ['true_index', 'predicted_index'], \
        'predictions.csv must have exactly the required two columns in order'

    expected_y, _, _, _, expected_predictions, _ = reference_results()
    assert len(df) == len(expected_y), \
        f'Expected one prediction for each of {len(expected_y)} frames, got {len(df)}'

    try:
        true_values = pd.to_numeric(df['true_index'], errors='raise').to_numpy(dtype=float)
        predicted_values = pd.to_numeric(df['predicted_index'], errors='raise').to_numpy(dtype=float)
    except Exception as exc:
        pytest.fail(f'Prediction columns must be numeric: {exc}')

    assert np.all(np.isfinite(true_values)), 'true_index contains non-finite values'
    assert np.all(np.isfinite(predicted_values)), 'predicted_index contains non-finite values'
    assert np.array_equal(true_values, expected_y), \
        'true_index must be the actual consecutive frame indices starting at 0'

    # Preserve the original MSE assertion, now with true_index tied to the video.
    try:
        mse = mean_squared_error(df['true_index'], df['predicted_index'])
    except Exception as exc:
        pytest.fail(f'Failed to compute MSE: {exc}')
    assert mse <= 5.0, f'MSE is {mse}, which is greater than the threshold of 5.0'

    # Check the predictions against answers independently derived from the video and
    # the specified standardization/PCA/regression procedure.
    agreement_mse = float(np.mean((predicted_values - expected_predictions) ** 2))
    assert agreement_mse <= 0.25, \
        f'Predictions do not match the specified video-derived model (MSE {agreement_mse})'


def collect_numeric_content(value):
    scalars = []
    vectors = []

    def visit(item):
        if isinstance(item, bool):
            return
        if isinstance(item, (int, float)):
            number = float(item)
            if math.isfinite(number):
                scalars.append(number)
            return
        if isinstance(item, list):
            if len(item) == 3 and all(
                not isinstance(v, bool) and isinstance(v, (int, float)) and math.isfinite(float(v))
                for v in item
            ):
                vectors.append(np.asarray(item, dtype=float))
            for child in item:
                visit(child)
            return
        if isinstance(item, dict):
            vals = list(item.values())
            if len(vals) == 3 and all(
                not isinstance(v, bool) and isinstance(v, (int, float)) and math.isfinite(float(v))
                for v in vals
            ):
                vectors.append(np.asarray(vals, dtype=float))
            for child in vals:
                visit(child)

    visit(value)
    return scalars, vectors


def test_model_artifacts_json():
    """Verify the artifact is valid and contains the fitted PCA/regression values."""
    assert os.path.exists(JSON_PATH), f'File not found: {JSON_PATH}'
    with open(JSON_PATH, 'r') as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            pytest.fail(f'Failed to parse {JSON_PATH} as JSON: {exc}')
    assert isinstance(data, dict), f'Expected JSON object in {JSON_PATH}'

    y, expected_vector, expected_slope, expected_intercept, _, _ = reference_results()
    df = pd.read_csv(CSV_PATH)
    submitted_predictions = pd.to_numeric(df['predicted_index'], errors='raise').to_numpy(dtype=float)
    submitted_mse = float(np.mean((y - submitted_predictions) ** 2))
    scalars, vectors = collect_numeric_content(data)

    matched_orientation = None
    for vector in vectors:
        norm = float(np.linalg.norm(vector))
        if norm == 0 or not math.isfinite(norm):
            continue
        unit = vector / norm
        dot = float(np.dot(unit, expected_vector))
        if abs(dot) >= 0.995 and abs(norm - 1.0) <= 0.02:
            matched_orientation = 1.0 if dot >= 0 else -1.0
            break
    assert matched_orientation is not None, \
        'model_artifacts.json does not contain the normalized dominant RGB eigenvector'

    oriented_slope = expected_slope * matched_orientation
    slope_tolerance = max(0.1, abs(oriented_slope) * 0.02)
    assert any(abs(v - oriented_slope) <= slope_tolerance for v in scalars), \
        'model_artifacts.json does not contain the fitted regression slope'
    assert any(abs(v - expected_intercept) <= 0.2 for v in scalars), \
        'model_artifacts.json does not contain the fitted regression intercept'
    mse_tolerance = max(0.1, submitted_mse * 0.05)
    assert any(abs(v - submitted_mse) <= mse_tolerance for v in scalars), \
        'model_artifacts.json does not contain the training MSE'


def test_cpp_pipeline_exists():
    """Preserve the original source existence assertion."""
    assert os.path.exists(CPP_PATH), f'File not found: {CPP_PATH}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
