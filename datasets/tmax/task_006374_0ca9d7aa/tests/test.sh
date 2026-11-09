#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/instrument
cat << 'PY_EOF' > /tmp/instrument/sitecustomize.py
import atexit
import json
import os

TRACE_PATH = os.environ.get("PLOT_TRACE_PATH")
events = []

def values(obj):
    try:
        import numpy as np
        return np.asarray(obj, dtype=float).reshape(-1).tolist()
    except Exception:
        return None

def flush():
    if TRACE_PATH:
        with open(TRACE_PATH, "w") as f:
            json.dump(events, f)

if TRACE_PATH:
    import matplotlib.pyplot as plt
    from matplotlib.figure import Figure

    original_scatter = plt.scatter
    original_plot = plt.plot
    original_savefig = plt.savefig
    original_show = plt.show
    original_figure_savefig = Figure.savefig

    def traced_scatter(x, y, *args, **kwargs):
        events.append({"op": "scatter", "x": values(x), "y": values(y)})
        return original_scatter(x, y, *args, **kwargs)

    def traced_plot(x, y, *args, **kwargs):
        events.append({"op": "plot", "x": values(x), "y": values(y)})
        return original_plot(x, y, *args, **kwargs)

    def traced_savefig(*args, **kwargs):
        target = args[0] if args else kwargs.get("fname")
        events.append({"op": "savefig", "target": os.fspath(target) if target is not None else None})
        return original_savefig(*args, **kwargs)

    def traced_figure_savefig(self, fname, *args, **kwargs):
        events.append({"op": "figure_savefig", "target": os.fspath(fname)})
        return original_figure_savefig(self, fname, *args, **kwargs)

    def traced_show(*args, **kwargs):
        events.append({"op": "show"})
        return original_show(*args, **kwargs)

    plt.scatter = traced_scatter
    plt.plot = traced_plot
    plt.savefig = traced_savefig
    plt.show = traced_show
    Figure.savefig = traced_figure_savefig
    atexit.register(flush)
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import math
import os
import subprocess
import sys

import matplotlib.image as mpimg
import numpy as np

DATA_FILE = "/home/user/data.csv"
BOOTSTRAP_FILE = "/home/user/bootstrap.csv"
SCRIPT_FILE = "/home/user/inference.py"
OUTPUT_PNG = "/home/user/output.png"
METRICS_JSON = "/home/user/metrics.json"
TRACE_FILE = "/tmp/plot_trace.json"


def read_lines(path):
    with open(path, "r") as f:
        return f.readlines()


def read_xy(path):
    rows = []
    for number, line in enumerate(read_lines(path), 1):
        fields = line.strip().split(",")
        assert len(fields) == 2, f"Invalid CSV row {number} in {path}."
        rows.append((float(fields[0]), float(fields[1])))
    return rows


def test_bootstrap_csv_exists_and_size():
    assert os.path.isfile(BOOTSTRAP_FILE), f"{BOOTSTRAP_FILE} does not exist."
    data_lines = read_lines(DATA_FILE)
    bootstrap_lines = read_lines(BOOTSTRAP_FILE)
    assert len(bootstrap_lines) == len(data_lines), \
        f"Expected {len(data_lines)} lines in {BOOTSTRAP_FILE}, found {len(bootstrap_lines)}."


def test_bootstrap_csv_content_and_sampling():
    data_lines = read_lines(DATA_FILE)
    bootstrap_lines = read_lines(BOOTSTRAP_FILE)
    data_set = set(data_lines)
    for i, line in enumerate(bootstrap_lines):
        assert line in data_set, \
            f"Line {i+1} in {BOOTSTRAP_FILE} is not from {DATA_FILE}: {line.strip()}"

    # A copied input is not a newly drawn bootstrap sample. With 100 draws, a
    # genuine with-replacement sample has a duplicate with overwhelming probability.
    assert bootstrap_lines != data_lines, "bootstrap.csv is just an unchanged copy of data.csv."
    counts = collections.Counter(bootstrap_lines)
    assert any(count > 1 for count in counts.values()), \
        "bootstrap.csv contains no repeated draw and does not demonstrate sampling with replacement."


def test_run_fixed_inference_on_bootstrap():
    assert os.path.isfile(SCRIPT_FILE), f"{SCRIPT_FILE} does not exist."
    for path in (OUTPUT_PNG, METRICS_JSON, TRACE_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    env["PLOT_TRACE_PATH"] = TRACE_FILE
    env["PYTHONPATH"] = "/tmp/instrument" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        [sys.executable, SCRIPT_FILE, BOOTSTRAP_FILE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"inference.py failed on bootstrap.csv:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(TRACE_FILE), "No plotting trace was produced while running inference.py."


def test_plot_contains_requested_data_and_is_saved_before_show():
    with open(TRACE_FILE, "r") as f:
        events = json.load(f)

    rows = read_xy(BOOTSTRAP_FILE)
    expected_points = sorted(rows)
    expected_line = sorted((x, 2.5 * x + 1.0) for x, _ in rows)

    scatter_indices = []
    line_indices = []
    valid_scatter = False
    valid_line = False
    save_indices = []
    show_indices = []

    for i, event in enumerate(events):
        op = event.get("op")
        if op == "scatter":
            scatter_indices.append(i)
            x, y = event.get("x"), event.get("y")
            if x is not None and y is not None and len(x) == len(y) == len(rows):
                actual = sorted(zip(x, y))
                valid_scatter = np.allclose(actual, expected_points, rtol=0, atol=1e-10)
        elif op == "plot":
            line_indices.append(i)
            x, y = event.get("x"), event.get("y")
            if x is not None and y is not None and len(x) == len(y) == len(rows):
                actual = sorted(zip(x, y))
                valid_line = np.allclose(actual, expected_line, rtol=0, atol=1e-10)
        elif op in ("savefig", "figure_savefig"):
            target = event.get("target")
            if target and os.path.basename(target) == "output.png":
                save_indices.append(i)
        elif op == "show":
            show_indices.append(i)

    assert valid_scatter, "The executed script did not scatter the bootstrap data points."
    assert valid_line, "The executed script did not plot the regression predictions for the bootstrap data."
    assert save_indices, "The executed script did not save output.png."
    first_save = min(save_indices)
    assert first_save > min(scatter_indices) and first_save > min(line_indices), \
        "output.png was saved before the data and regression line were plotted."
    if show_indices:
        assert first_save < min(show_indices), \
            "The plot is still saved after plt.show(); save output.png before displaying the figure."


def test_output_png_validity():
    assert os.path.isfile(OUTPUT_PNG), f"{OUTPUT_PNG} does not exist."
    file_size = os.path.getsize(OUTPUT_PNG)
    assert file_size > 5000, \
        f"{OUTPUT_PNG} is too small ({file_size} bytes). It appears to be a blank plot."
    with open(OUTPUT_PNG, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{OUTPUT_PNG} is not a PNG file."
    image = mpimg.imread(OUTPUT_PNG)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, \
        "output.png has invalid image dimensions."
    rgb = image[..., :3] if image.ndim == 3 else image
    assert float(np.ptp(rgb)) > 0.1, "output.png is visually blank."
    if image.ndim == 3:
        nonwhite = np.any(image[..., :3] < 0.98, axis=-1)
    else:
        nonwhite = image < 0.98
    assert float(nonwhite.mean()) > 0.005, "output.png contains essentially no plotted content."


def test_metrics_json_validity_and_value():
    assert os.path.isfile(METRICS_JSON), f"{METRICS_JSON} does not exist."
    with open(METRICS_JSON, "r") as f:
        metrics = json.load(f)
    assert "mean_error" in metrics, f"'mean_error' key missing from {METRICS_JSON}."
    assert isinstance(metrics["mean_error"], (int, float)) and not isinstance(metrics["mean_error"], bool), \
        "'mean_error' should be a number."
    assert math.isfinite(float(metrics["mean_error"])), "'mean_error' must be finite."
    rows = read_xy(BOOTSTRAP_FILE)
    expected = sum(y - (2.5 * x + 1.0) for x, y in rows) / len(rows)
    assert math.isclose(float(metrics["mean_error"]), expected, rel_tol=1e-12, abs_tol=1e-12), \
        f"mean_error was not computed from bootstrap.csv: expected {expected}, got {metrics['mean_error']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
