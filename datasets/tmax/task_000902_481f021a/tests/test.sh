#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import runpy
import time

import numpy as np
import pandas as pd
import pytest

RAW_PATH = "/home/user/data/raw_data.csv"
PROCESSED_PATH = "/home/user/data/processed_data.csv"
METRICS_PATH = "/home/user/metrics.json"


def test_processed_data_exists_and_format():
    assert os.path.exists(PROCESSED_PATH), "Processed data file is missing."

    with open(PROCESSED_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "Processed data is empty."

        expected_cols = ["id", "text", "value_1", "value_2", "target", "seq_length"]
        for col in expected_cols:
            assert col in header, f"Missing column '{col}' in processed_data.csv"
        assert header == expected_cols, "Processed data must keep the original columns and append seq_length."

        rows = list(reader)
        assert len(rows) == 1000, f"Expected 1000 rows, found {len(rows)}."


def test_processed_data_values_and_row_correspondence():
    raw_v1 = []
    raw_v2 = []
    with open(RAW_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["value_1"]:
                raw_v1.append(float(row["value_1"]))
            raw_v2.append(float(row["value_2"]))

    raw_v1.sort()
    n = len(raw_v1)
    if n % 2 == 0:
        median_v1 = (raw_v1[n // 2 - 1] + raw_v1[n // 2]) / 2.0
    else:
        median_v1 = raw_v1[n // 2]

    raw_v2.sort()

    def get_percentile(data, p):
        k = (len(data) - 1) * (p / 100.0)
        f = math.floor(k)
        c = math.ceil(k)
        if f == c:
            return data[int(k)]
        d0 = data[int(f)] * (c - k)
        d1 = data[int(c)] * (k - f)
        return d0 + d1

    p5 = get_percentile(raw_v2, 5)
    p95 = get_percentile(raw_v2, 95)

    with open(PROCESSED_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            v1 = float(row["value_1"])
            assert not math.isnan(v1), "value_1 contains NaN"

            v2 = float(row["value_2"])
            assert v2 >= p5 - 1e-5, f"value_2 not clipped at 5th percentile: {v2} < {p5}"
            assert v2 <= p95 + 1e-5, f"value_2 not clipped at 95th percentile: {v2} > {p95}"

            text = row["text"]
            seq_len = int(row["seq_length"])
            assert seq_len == len(text.split()), f"seq_length incorrect for text: '{text}'"

    raw = pd.read_csv(RAW_PATH)
    processed = pd.read_csv(PROCESSED_PATH)

    assert raw["id"].is_unique, "Raw ids must be unique for correspondence checking."
    assert processed["id"].is_unique, "Processed data contains duplicate ids."
    assert set(processed["id"].tolist()) == set(raw["id"].tolist()), "Processed ids do not match raw data."

    corresponding_raw = raw.set_index("id").loc[processed["id"].tolist()].reset_index()
    assert processed["text"].tolist() == corresponding_raw["text"].tolist(), "text was changed or assigned to the wrong row."
    assert np.allclose(processed["target"], corresponding_raw["target"], rtol=1e-12, atol=1e-12), "target was changed or assigned to the wrong row."

    expected_v1 = corresponding_raw["value_1"].fillna(raw["value_1"].median()).to_numpy()
    expected_v2 = corresponding_raw["value_2"].clip(raw["value_2"].quantile(0.05), raw["value_2"].quantile(0.95)).to_numpy()
    expected_seq = corresponding_raw["text"].map(lambda text: len(text.split())).to_numpy()

    assert np.allclose(processed["value_1"], expected_v1, rtol=1e-12, atol=1e-10), "value_1 is not the raw value with only missing entries median-imputed."
    assert np.allclose(processed["value_2"], expected_v2, rtol=1e-12, atol=1e-10), "value_2 does not exactly correspond to percentile clipping of the raw row."
    assert np.array_equal(processed["seq_length"].to_numpy(), expected_seq), "seq_length does not correspond to each raw row's text."


def test_metrics_json_matches_random_forest_and_live_benchmark():
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.metrics import mean_squared_error

    assert os.path.exists(METRICS_PATH), "metrics.json is missing."
    with open(METRICS_PATH, "r", encoding="utf-8") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("metrics.json is not valid JSON.")

    assert "mse" in metrics, "Missing 'mse' key in metrics.json"
    assert "avg_inference_sec" in metrics, "Missing 'avg_inference_sec' key in metrics.json"
    assert set(metrics) == {"mse", "avg_inference_sec"}, "metrics.json must contain the exact requested keys."

    assert isinstance(metrics["mse"], (int, float)) and not isinstance(metrics["mse"], bool), "'mse' must be a number."
    assert isinstance(metrics["avg_inference_sec"], (int, float)) and not isinstance(metrics["avg_inference_sec"], bool), "'avg_inference_sec' must be a number."
    assert math.isfinite(metrics["mse"]), "MSE must be finite."
    assert math.isfinite(metrics["avg_inference_sec"]), "Average inference time must be finite."
    assert metrics["mse"] > 0, "MSE should be positive."
    assert metrics["avg_inference_sec"] >= 0, "Average inference time should be non-negative."
    assert metrics["mse"] == round(metrics["mse"], 4), "MSE must be rounded to 4 decimal places."
    assert metrics["avg_inference_sec"] == round(metrics["avg_inference_sec"], 4), "Average inference time must be rounded to 4 decimal places."

    processed = pd.read_csv(PROCESSED_PATH)
    X = processed[["value_1", "value_2", "seq_length"]]
    y = processed["target"]
    model = RandomForestRegressor(random_state=42)
    model.fit(X, y)
    predictions = model.predict(X)
    expected_mse = round(float(mean_squared_error(y, predictions)), 4)
    assert math.isclose(float(metrics["mse"]), expected_mse, rel_tol=0, abs_tol=5e-5), \
        f"Reported MSE {metrics['mse']} does not match the RandomForestRegressor training MSE {expected_mse}."

    # Compare the reported benchmark to several fresh 10-call benchmarks. The
    # multiplicative allowance accounts for normal shared-container timing noise
    # while rejecting arbitrary values unrelated to predict() runtime.
    batch_averages = []
    for _ in range(3):
        start = time.perf_counter()
        for _ in range(10):
            model.predict(X)
        batch_averages.append((time.perf_counter() - start) / 10.0)
    live_average = float(np.median(batch_averages))
    reported = float(metrics["avg_inference_sec"])
    lower = max(0.0, live_average / 10.0 - 0.0001)
    upper = live_average * 10.0 + 0.002
    assert lower <= reported <= upper, \
        f"Reported inference time {reported} is inconsistent with a 10-run predict benchmark (observed about {live_average:.6f}s)."


def test_plot_script_executes_and_plots_requested_columns():
    import matplotlib
    matplotlib.use("Agg", force=True)
    import matplotlib.image as mpimg
    import matplotlib.pyplot as plt
    from matplotlib.axes import Axes

    script_path = "/home/user/plot_data.py"
    assert os.path.exists(script_path), "plot_data.py is missing."

    img_path = "/home/user/scatter.png"
    assert os.path.exists(img_path), "scatter.png is missing."

    captured = []
    original_scatter = Axes.scatter
    original_show = plt.show

    def recording_scatter(self, x, y, *args, **kwargs):
        captured.append((np.asarray(x).copy(), np.asarray(y).copy()))
        return original_scatter(self, x, y, *args, **kwargs)

    def forbidden_show(*args, **kwargs):
        raise AssertionError("plot_data.py attempted to open an interactive window with show().")

    Axes.scatter = recording_scatter
    plt.show = forbidden_show
    old_cwd = os.getcwd()
    old_display = os.environ.pop("DISPLAY", None)
    os.environ["MPLBACKEND"] = "Agg"
    try:
        os.remove(img_path)
        os.chdir("/home/user")
        runpy.run_path(script_path, run_name="__main__")
    finally:
        os.chdir(old_cwd)
        Axes.scatter = original_scatter
        plt.show = original_show
        if old_display is not None:
            os.environ["DISPLAY"] = old_display
        else:
            os.environ.pop("DISPLAY", None)

    assert os.path.exists(img_path), "Running plot_data.py did not recreate scatter.png."

    processed = pd.read_csv(PROCESSED_PATH)
    expected_x = processed["seq_length"].to_numpy(dtype=float)
    expected_y = processed["target"].to_numpy(dtype=float)
    matching_call = False
    for x, y in captured:
        try:
            x = np.asarray(x, dtype=float).reshape(-1)
            y = np.asarray(y, dtype=float).reshape(-1)
        except (TypeError, ValueError):
            continue
        if x.shape == expected_x.shape and y.shape == expected_y.shape:
            if np.allclose(x, expected_x, rtol=0, atol=0) and np.allclose(y, expected_y, rtol=1e-12, atol=1e-12):
                matching_call = True
                break
    assert matching_call, "plot_data.py did not scatter seq_length against target from processed_data.csv."

    with open(img_path, "rb") as f:
        header = f.read(8)
        assert header == b"\x89PNG\r\n\x1a\n", "scatter.png is not a valid PNG file."
    assert os.path.getsize(img_path) > 1000, "scatter.png is unexpectedly empty or trivial."
    image = mpimg.imread(img_path)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, "scatter.png is not a usable rendered plot."
    assert float(np.nanstd(image)) > 0.01, "scatter.png contains no meaningful rendered content."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
