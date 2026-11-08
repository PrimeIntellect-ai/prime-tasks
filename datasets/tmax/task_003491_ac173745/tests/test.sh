#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from PIL import Image, ImageStat


def test_waveform_png_exists_and_valid():
    """Execute the repaired visualizer and verify it plots the raw first second."""
    img_path = "/home/user/waveform.png"
    capture_path = "/tmp/waveform_capture.json"
    for path in (img_path, capture_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    harness = r'''
import json
import runpy
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.axes
from scipy.io import wavfile

sr, expected = wavfile.read("/app/sensor_data.wav")
expected = np.asarray(expected[:sr])
record = {"matched_raw_first_second": False, "candidate_lengths": []}
original_plot = matplotlib.axes.Axes.plot

def checked_plot(self, *args, **kwargs):
    for arg in args:
        try:
            arr = np.asarray(arg)
        except Exception:
            continue
        if arr.ndim >= 1:
            record["candidate_lengths"].append(int(arr.shape[0]))
        if arr.shape == expected.shape and np.array_equal(arr, expected):
            record["matched_raw_first_second"] = True
    return original_plot(self, *args, **kwargs)

matplotlib.axes.Axes.plot = checked_plot
try:
    runpy.run_path("/app/visualize.py", run_name="__main__")
finally:
    with open("/tmp/waveform_capture.json", "w") as f:
        json.dump(record, f)
'''
    result = subprocess.run(
        [sys.executable, "-c", harness], capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, (
        "Running /app/visualize.py failed:\n" + result.stdout + result.stderr
    )

    assert os.path.exists(img_path), f"{img_path} does not exist. Did you fix and run visualize.py?"

    try:
        with Image.open(img_path) as img:
            img.verify()
        with Image.open(img_path) as img:
            rgb = img.convert("RGB")
            assert rgb.width >= 200 and rgb.height >= 100, "waveform.png is implausibly small."
            stat = ImageStat.Stat(rgb)
            assert max(stat.var) > 1.0, "waveform.png appears blank or uniform."
            colors = rgb.getcolors(maxcolors=1000000)
            assert colors is None or len(colors) > 10, "waveform.png lacks plotted image content."
    except AssertionError:
        raise
    except Exception as e:
        pytest.fail(f"Failed to open {img_path} as a valid image. The script might still be broken: {e}")

    assert os.path.exists(capture_path), "The visualization execution produced no plot capture."
    with open(capture_path) as f:
        capture = json.load(f)
    assert capture.get("matched_raw_first_second") is True, (
        "visualize.py did not pass the raw samples from the first second of "
        "/app/sensor_data.wav to the plotting API."
    )


def test_pipeline_script_exists():
    """Verify that the pipeline.py script was created."""
    script_path = "/home/user/pipeline.py"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."


def test_metrics_json_and_mse_threshold():
    """Execute and instrument the pipeline, then validate its reported test MSE."""
    script_path = "/home/user/pipeline.py"
    metrics_path = "/home/user/metrics.json"
    events_path = "/tmp/pipeline_events.json"
    assert os.path.exists(script_path), f"{script_path} does not exist."

    for path in (metrics_path, events_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    harness = r'''
import json
import os
import runpy
import sys
import numpy as np
from sklearn.linear_model import LinearRegression

record = {"opened": [], "fits": [], "predictions": []}

def audit(event, args):
    if event == "open" and args:
        try:
            record["opened"].append(os.path.abspath(os.fspath(args[0])))
        except Exception:
            pass

sys.addaudithook(audit)
original_fit = LinearRegression.fit
original_predict = LinearRegression.predict

def checked_fit(self, X, y, *args, **kwargs):
    xa = np.asarray(X)
    ya = np.asarray(y).reshape(-1)
    record["fits"].append({
        "model": id(self),
        "x_shape": list(xa.shape),
        "x": xa.tolist(),
        "y": ya.tolist(),
    })
    return original_fit(self, X, y, *args, **kwargs)

def checked_predict(self, X, *args, **kwargs):
    result = original_predict(self, X, *args, **kwargs)
    xa = np.asarray(X)
    record["predictions"].append({
        "model": id(self),
        "x_shape": list(xa.shape),
        "x": xa.tolist(),
        "values": np.asarray(result).reshape(-1).tolist(),
    })
    return result

LinearRegression.fit = checked_fit
LinearRegression.predict = checked_predict
try:
    runpy.run_path("/home/user/pipeline.py", run_name="__main__")
finally:
    with open("/tmp/pipeline_events.json", "w") as f:
        json.dump(record, f)
'''
    result = subprocess.run(
        [sys.executable, "-c", harness], capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, "Running pipeline.py failed:\n" + result.stdout + result.stderr
    assert os.path.exists(events_path), "No pipeline execution record was produced."

    with open(events_path) as f:
        events = json.load(f)

    opened = set(events.get("opened", []))
    assert "/app/sensor_data.wav" in opened, "pipeline.py did not load /app/sensor_data.wav."
    assert "/app/targets.csv" in opened, "pipeline.py did not load /app/targets.csv."

    target_frame = pd.read_csv("/app/targets.csv")
    assert len(target_frame.columns) >= 1
    targets = target_frame.iloc[:, 0].to_numpy(dtype=float)
    split = int(len(targets) * 0.8)
    train_targets = targets[:split]
    test_targets = targets[split:]

    valid_pair = None
    for fit in events.get("fits", []):
        shape = fit.get("x_shape", [])
        fit_y = np.asarray(fit.get("y", []), dtype=float)
        if len(shape) != 2 or shape[0] != split or shape[1] < 2:
            continue
        if fit_y.shape != train_targets.shape or not np.allclose(fit_y, train_targets):
            continue
        for pred in events.get("predictions", []):
            pshape = pred.get("x_shape", [])
            values = np.asarray(pred.get("values", []), dtype=float)
            if pred.get("model") != fit.get("model"):
                continue
            if len(pshape) == 2 and pshape[0] == len(test_targets) and pshape[1] == shape[1] and values.shape == test_targets.shape:
                valid_pair = (fit, pred, values)
                break
        if valid_pair is not None:
            break

    assert valid_pair is not None, (
        "pipeline.py must fit sklearn LinearRegression on the chronological first 80% "
        "and predict the final 20% using at least two features."
    )

    fit, pred, predictions = valid_pair
    all_features = np.vstack([
        np.asarray(fit["x"], dtype=float),
        np.asarray(pred["x"], dtype=float),
    ])
    assert np.isfinite(all_features).all(), "Extracted features contain non-finite values."
    varying_columns = np.sum(np.ptp(all_features, axis=0) > 0)
    assert varying_columns >= 2, "At least two extracted features must vary across the audio chunks."
    assert np.isfinite(predictions).all(), "LinearRegression produced non-finite predictions."
    measured_mse = float(np.mean((test_targets - predictions) ** 2))

    assert os.path.exists(metrics_path), f"{metrics_path} does not exist. Did you run the pipeline script?"
    with open(metrics_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse {metrics_path} as JSON.")

    assert "test_mse" in data, "The key 'test_mse' was not found in metrics.json."
    test_mse = data["test_mse"]
    assert isinstance(test_mse, (int, float)), f"'test_mse' should be a number, but got {type(test_mse).__name__}."
    assert not isinstance(test_mse, bool), "'test_mse' must be a numeric MSE, not a boolean."
    assert math.isfinite(test_mse) and test_mse >= 0, "'test_mse' must be finite and non-negative."
    assert math.isclose(float(test_mse), measured_mse, rel_tol=1e-5, abs_tol=1e-6), (
        f"metrics.json reports {test_mse}, but the executed model's predictions give MSE {measured_mse}."
    )

    threshold = 1.5
    assert test_mse <= threshold, f"Fail: MSE too high. Measured test_mse is {test_mse}, which exceeds the threshold of {threshold}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
