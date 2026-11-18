#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import runpy
import stat
from collections import Counter, defaultdict

os.environ["MPLBACKEND"] = "Agg"

SCRIPT = "/home/user/prepare_data.py"
METADATA = "/home/user/metadata.csv"
BENCHMARKS = "/home/user/benchmarks.csv"
SUMMARY = "/home/user/summary.csv"
PLOT = "/home/user/benchmark_plot.png"

EXPECTED_METADATA = b"model_id,architecture\n101,transformer\n102,cnn\n103,rnn\n104,transformer\n105,cnn\n"
EXPECTED_BENCHMARKS = b"id ,inference_ms\n101 ,45.2\n102 ,12.5\n103 ,25.1\n104 ,48.8\n105 ,14.3\n"


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def derive_expected():
    with open(METADATA, newline="") as f:
        metadata_rows = list(csv.DictReader(f))
    with open(BENCHMARKS, newline="") as f:
        benchmark_rows = list(csv.DictReader(f))

    metadata = {
        row["model_id"].strip(): row["architecture"].strip()
        for row in metadata_rows
    }
    grouped = defaultdict(list)
    for row in benchmark_rows:
        cleaned = {key.strip(): value.strip() for key, value in row.items()}
        model_id = cleaned["id"]
        if model_id in metadata:
            grouped[metadata[model_id]].append(float(cleaned["inference_ms"]))
    return {arch: sum(values) / len(values) for arch, values in grouped.items()}


def execute_script_and_capture_bars():
    import matplotlib
    matplotlib.use("Agg", force=True)
    import matplotlib.axes
    import matplotlib.pyplot as plt
    import numpy as np

    calls = []
    original_bar = matplotlib.axes.Axes.bar

    def recording_bar(self, x, height, *args, **kwargs):
        try:
            heights = np.asarray(height).reshape(-1)
            xs = np.asarray(x).reshape(-1)
            calls.append((xs.tolist(), [float(value) for value in heights]))
        except Exception:
            pass
        return original_bar(self, x, height, *args, **kwargs)

    matplotlib.axes.Axes.bar = recording_bar
    try:
        runpy.run_path(SCRIPT, run_name="__main__")
    finally:
        matplotlib.axes.Axes.bar = original_bar
        plt.close("all")
    return calls


def test_script_and_inputs():
    assert os.path.exists(SCRIPT), f"File {SCRIPT} is missing."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"File {SCRIPT} must be a regular Python file."
    with open(SCRIPT, "rb") as f:
        source = f.read()
    compile(source, SCRIPT, "exec")

    assert read_bytes(METADATA) == EXPECTED_METADATA, "metadata.csv was modified."
    assert read_bytes(BENCHMARKS) == EXPECTED_BENCHMARKS, "benchmarks.csv was modified."

    for output in (SUMMARY, PLOT):
        if os.path.lexists(output):
            os.remove(output)

    calls = execute_script_and_capture_bars()

    assert read_bytes(METADATA) == EXPECTED_METADATA, "prepare_data.py modified metadata.csv."
    assert read_bytes(BENCHMARKS) == EXPECTED_BENCHMARKS, "prepare_data.py modified benchmarks.csv."

    expected_values = sorted(derive_expected().values())
    recorded = [height for _, heights in calls for height in heights if math.isfinite(height)]
    matching_vector = any(
        len(heights) == len(expected_values)
        and all(abs(a - b) < 1e-5 for a, b in zip(sorted(heights), expected_values))
        for _, heights in calls
    )
    matching_all = (
        len(recorded) == len(expected_values)
        and all(abs(a - b) < 1e-5 for a, b in zip(sorted(recorded), expected_values))
    )
    assert matching_vector or matching_all, (
        "prepare_data.py did not create bars whose heights are the grouped average inference times."
    )


def test_summary_csv():
    path = SUMMARY
    assert os.path.isfile(path), f"File {path} is missing. The script did not generate it."

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"File {path} is empty."

    header = rows[0]
    assert header == ["architecture", "inference_ms"], f"Header in {path} is incorrect. Expected ['architecture', 'inference_ms'], got {header}"

    expected_data = {
        "cnn": 13.4,
        "rnn": 25.1,
        "transformer": 47.0
    }
    derived_data = derive_expected()
    assert derived_data == expected_data

    actual_data = {}
    assert len(rows[1:]) == len(derived_data), f"Expected exactly {len(derived_data)} data rows, got {len(rows[1:])}."
    for row in rows[1:]:
        assert len(row) == 2, f"Row {row} does not have exactly 2 columns."
        arch, val = row
        assert arch not in actual_data, f"Architecture '{arch}' appears more than once."
        try:
            actual_data[arch] = float(val)
        except ValueError:
            assert False, f"Could not parse '{val}' as float in row {row}."

    assert len(actual_data) == 3, f"Expected 3 rows of data, got {len(actual_data)}."

    for arch, expected_val in expected_data.items():
        assert arch in actual_data, f"Architecture '{arch}' is missing from summary.csv."
        assert abs(actual_data[arch] - expected_val) < 1e-5, f"Expected {expected_val} for {arch}, got {actual_data[arch]}."


def test_benchmark_plot_png():
    from PIL import Image
    import numpy as np

    path = PLOT
    assert os.path.isfile(path), f"File {path} is missing. The script did not generate it."

    file_size = os.path.getsize(path)
    assert file_size > 5000, f"File {path} is suspiciously small ({file_size} bytes), indicating an empty or invalid plot."

    with open(path, "rb") as f:
        magic_bytes = f.read(8)

    expected_magic = b"\x89PNG\r\n\x1a\n"
    assert magic_bytes == expected_magic, f"File {path} is not a valid PNG image. Magic bytes mismatch."

    with Image.open(path) as image:
        image.verify()
    with Image.open(path) as image:
        pixels = np.asarray(image.convert("RGB"))

    assert pixels.shape[0] >= 100 and pixels.shape[1] >= 100, "Plot image dimensions are too small."
    assert float(pixels.std()) > 5.0, "Plot image is visually blank."

    counts = Counter(map(tuple, pixels.reshape(-1, 3)))
    candidate_colors = [
        color for color, count in counts.most_common(64)
        if count >= 200 and not all(channel >= 240 for channel in color)
    ]

    rectangles = []
    for color in candidate_colors:
        mask = np.all(pixels == np.asarray(color), axis=2)
        run_counts = Counter()
        for row in mask:
            indices = np.flatnonzero(row)
            if indices.size == 0:
                continue
            split_points = np.where(np.diff(indices) > 1)[0] + 1
            for run in np.split(indices, split_points):
                if run.size >= 12:
                    run_counts[(int(run[0]), int(run[-1]))] += 1
        for (left, right), repeated_rows in run_counts.items():
            if repeated_rows >= 12:
                rectangles.append(((left + right) / 2.0, right - left + 1, repeated_rows))

    distinct_centers = []
    for center, width, height in sorted(rectangles, key=lambda item: item[2], reverse=True):
        if not any(abs(center - existing) < 8 for existing in distinct_centers):
            distinct_centers.append(center)

    assert len(distinct_centers) >= 3, (
        "benchmark_plot.png does not contain at least three substantial filled bar-shaped regions."
    )


test_script_and_inputs()
test_summary_csv()
test_benchmark_plot_png()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
