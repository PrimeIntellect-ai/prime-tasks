#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrument
cat <<'PY_EOF' > /tmp/verifier_instrument/sitecustomize.py
import json
import os
import numpy as np
from matplotlib.figure import Figure

_original_savefig = Figure.savefig

def _recording_savefig(self, fname, *args, **kwargs):
    event = {"target": os.path.abspath(os.fspath(fname)), "axes": []}
    for ax in self.axes:
        collections = []
        for collection in ax.collections:
            try:
                collections.append(np.asarray(collection.get_offsets(), dtype=float).tolist())
            except Exception:
                collections.append([])
        event["axes"].append({
            "xlabel": ax.get_xlabel(),
            "ylabel": ax.get_ylabel(),
            "collections": collections,
        })

    result = _original_savefig(self, fname, *args, **kwargs)
    trace_path = os.environ.get("PLOT_TRACE_PATH")
    if trace_path:
        with open(trace_path, "a", encoding="utf-8") as trace_file:
            trace_file.write(json.dumps(event) + "\n")
    return result

Figure.savefig = _recording_savefig
PY_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression

WORKSPACE_DIR = "/home/user/workspace"
ANALYSIS_PATH = os.path.join(WORKSPACE_DIR, "analysis.py")
SENSOR_A_PATH = os.path.join(WORKSPACE_DIR, "sensor_A.csv")
SENSOR_B_PATH = os.path.join(WORKSPACE_DIR, "sensor_B.csv")
MODEL_RESULTS_PATH = os.path.join(WORKSPACE_DIR, "model_results.json")
PREDICTIONS_IMAGE_PATH = os.path.join(WORKSPACE_DIR, "predictions.png")
TRACE_PATH = "/tmp/plot_trace.jsonl"

ORIGINAL_A = """id,temp,pressure
1,20.5,1010
2,21.0,1012
3,150.0,1008
4,19.5,1015
5,22.1,1011
"""
ORIGINAL_B = """id,humidity
1,45.0
2,46.5
3,40.0
4,
5,48.0
"""

DYNAMIC_A = """id,temp,pressure
10,10.0,100
11,20.0,110
12,70.0,120
13,30.0,105
14,40.0,130
99,999.0,999
"""
DYNAMIC_B = """id,humidity
14,4.0
10,1.0
11,
12,100.0
13,3.0
200,8.0
"""


def expected_for(a_text, b_text):
    from io import StringIO
    df_a = pd.read_csv(StringIO(a_text))
    df_b = pd.read_csv(StringIO(b_text))
    merged = df_a.merge(df_b, on="id", how="inner")
    merged["humidity"] = merged["humidity"].fillna(merged["humidity"].median())
    cleaned = merged[~(merged["temp"] > 50)].copy()
    X = cleaned[["pressure", "humidity"]]
    y = cleaned["temp"]
    model = LinearRegression()
    model.fit(X, y)
    predictions = model.predict(X)
    results = {
        "pressure_coef": round(float(model.coef_[0]), 4),
        "humidity_coef": round(float(model.coef_[1]), 4),
        "intercept": round(float(model.intercept_), 4),
    }
    return results, y.to_numpy(dtype=float), np.asarray(predictions, dtype=float)


def run_analysis(a_text, b_text):
    with open(SENSOR_A_PATH, "w", encoding="utf-8") as f:
        f.write(a_text)
    with open(SENSOR_B_PATH, "w", encoding="utf-8") as f:
        f.write(b_text)

    for path in (MODEL_RESULTS_PATH, PREDICTIONS_IMAGE_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_instrument" + os.pathsep + env.get("PYTHONPATH", "")
    env["PLOT_TRACE_PATH"] = TRACE_PATH
    env.pop("DISPLAY", None)
    env.pop("MPLBACKEND", None)

    try:
        completed = subprocess.run(
            [sys.executable, ANALYSIS_PATH],
            cwd=WORKSPACE_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("analysis.py hung when executed on a headless server")

    assert completed.returncode == 0, (
        "analysis.py did not run successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def load_results():
    assert os.path.isfile(MODEL_RESULTS_PATH), (
        f"File {MODEL_RESULTS_PATH} does not exist. The script might not have run successfully."
    )
    with open(MODEL_RESULTS_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {MODEL_RESULTS_PATH} is not valid JSON.") from exc


def assert_plot(expected_true, expected_predicted):
    assert os.path.isfile(PREDICTIONS_IMAGE_PATH), (
        f"File {PREDICTIONS_IMAGE_PATH} does not exist. The plot was not saved."
    )

    with open(PREDICTIONS_IMAGE_PATH, "rb") as f:
        header = f.read(8)
    png_signature = b'\x89PNG\r\n\x1a\n'
    assert header == png_signature, f"File {PREDICTIONS_IMAGE_PATH} is not a valid PNG image."
    assert os.path.getsize(PREDICTIONS_IMAGE_PATH) > 100, (
        f"File {PREDICTIONS_IMAGE_PATH} is too small to be a valid plot."
    )

    image = mpimg.imread(PREDICTIONS_IMAGE_PATH)
    assert image.size > 0 and float(np.nanstd(image)) > 1e-8, "predictions.png is blank"

    assert os.path.isfile(TRACE_PATH), "The script did not save a matplotlib figure"
    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]

    expected_target = os.path.abspath(PREDICTIONS_IMAGE_PATH)
    matching_events = [event for event in events if event.get("target") == expected_target]
    assert matching_events, "The script did not save the plotted figure to predictions.png"

    expected_points = np.column_stack([expected_true, expected_predicted])
    found_scatter = False
    for event in matching_events:
        for axis in event.get("axes", []):
            xlabel = str(axis.get("xlabel", "")).lower()
            ylabel = str(axis.get("ylabel", "")).lower()
            if "true" not in xlabel or "predict" not in ylabel:
                continue
            for offsets in axis.get("collections", []):
                points = np.asarray(offsets, dtype=float)
                if points.shape == expected_points.shape and np.allclose(points, expected_points, rtol=1e-7, atol=1e-7):
                    found_scatter = True
    assert found_scatter, (
        "The saved figure must contain a True-vs-Predicted scatter plot from the fitted model"
    )


def assert_results_equal(results, expected):
    expected_keys = {"pressure_coef", "humidity_coef", "intercept"}
    assert set(results.keys()) == expected_keys, (
        f"JSON keys do not match expected keys. Found: {list(results.keys())}"
    )
    for key in expected_keys:
        assert isinstance(results[key], (int, float)) and not isinstance(results[key], bool)
        assert abs(float(results[key]) - expected[key]) < 1e-4, (
            f"Expected {key} to be {expected[key]}, got {results[key]}"
        )


def test_complete_pipeline_executes_and_produces_real_outputs():
    assert os.path.isfile(ANALYSIS_PATH), f"File {ANALYSIS_PATH} does not exist."
    assert os.path.getsize(ANALYSIS_PATH) > 0, "analysis.py is empty"

    old_a = open(SENSOR_A_PATH, "rb").read()
    old_b = open(SENSOR_B_PATH, "rb").read()
    try:
        # Preserve the original verifier's exact checks on the supplied data.
        run_analysis(ORIGINAL_A, ORIGINAL_B)
        results = load_results()
        expected_keys = {"pressure_coef", "humidity_coef", "intercept"}
        assert set(results.keys()) == expected_keys, f"JSON keys do not match expected keys. Found: {list(results.keys())}"
        assert abs(results["pressure_coef"] - (-0.3204)) < 1e-4, f"Expected pressure_coef to be -0.3204, got {results['pressure_coef']}"
        assert abs(results["humidity_coef"] - 0.8177) < 1e-4, f"Expected humidity_coef to be 0.8177, got {results['humidity_coef']}"
        assert abs(results["intercept"] - 307.2144) < 1e-4, f"Expected intercept to be 307.2144, got {results['intercept']}"
        original_expected, original_true, original_predicted = expected_for(ORIGINAL_A, ORIGINAL_B)
        assert_results_equal(results, original_expected)
        assert_plot(original_true, original_predicted)

        # A second, verifier-derived case detects hardcoded artifacts and exercises
        # inner joining, median imputation before filtering, outlier removal, and fitting.
        run_analysis(DYNAMIC_A, DYNAMIC_B)
        dynamic_expected, dynamic_true, dynamic_predicted = expected_for(DYNAMIC_A, DYNAMIC_B)
        dynamic_results = load_results()
        assert_results_equal(dynamic_results, dynamic_expected)
        assert_plot(dynamic_true, dynamic_predicted)
    finally:
        with open(SENSOR_A_PATH, "wb") as f:
            f.write(old_a)
        with open(SENSOR_B_PATH, "wb") as f:
            f.write(old_b)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
