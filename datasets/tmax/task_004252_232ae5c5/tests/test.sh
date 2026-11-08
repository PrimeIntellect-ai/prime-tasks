#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import uuid
import tempfile
import subprocess

import cv2
import numpy as np
import pandas as pd
import pytest
import torch
import torch.nn as nn


def test_frame_scores_csv():
    path = "/home/user/frame_scores.csv"
    assert os.path.isfile(path), f"Missing frame_scores.csv at {path}"

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "frame_scores.csv is empty"

        expected_cols = ["frame_index", "timestamp_sec", "visibility_score"]
        for col in expected_cols:
            assert col in header, f"Column '{col}' missing from frame_scores.csv header"

        rows = list(reader)
        assert len(rows) > 0, "frame_scores.csv has no data rows"


def _reference_frame_scores():
    class VisibilityModel(nn.Module):
        def __init__(self):
            super().__init__()
            self.conv1 = nn.Conv2d(1, 16, 3, padding=1)
            self.fc = nn.Linear(16 * 64 * 64, 1)

        def forward(self, x):
            x = self.conv1(x)
            x = x.view(x.size(0), -1)
            return self.fc(x)

    model = VisibilityModel()
    try:
        state = torch.load('/app/model/weights.pth', map_location='cpu', weights_only=True)
    except TypeError:
        state = torch.load('/app/model/weights.pth', map_location='cpu')
    model.load_state_dict(state)
    model.eval()

    cap = cv2.VideoCapture('/app/dashcam.mp4')
    assert cap.isOpened(), "Could not open source video"
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.resize(gray, (64, 64), interpolation=cv2.INTER_LINEAR)
        frames.append(gray.astype(np.float32) / 255.0)
    cap.release()

    outputs = []
    with torch.no_grad():
        for start in range(0, len(frames), 16):
            batch = torch.from_numpy(np.stack(frames[start:start + 16])[:, None, :, :])
            outputs.extend(model(batch).reshape(-1).cpu().numpy().astype(float).tolist())
    return np.asarray(outputs, dtype=float)


def test_frame_scores_values_and_coverage():
    df = pd.read_csv('/home/user/frame_scores.csv')
    required = ['frame_index', 'timestamp_sec', 'visibility_score']
    assert all(c in df.columns for c in required)
    assert not df[required].isnull().any().any(), "Frame score fields contain missing values"

    for c in required:
        df[c] = pd.to_numeric(df[c], errors='raise')
    assert np.isfinite(df[required].to_numpy(dtype=float)).all(), "Frame score fields must be finite"

    expected_scores = _reference_frame_scores()
    n = len(expected_scores)
    assert n == 300, f"Unexpected source video frame count: {n}"
    assert len(df) == n, f"Expected one row for each of {n} frames, got {len(df)}"
    assert np.array_equal(df['frame_index'].to_numpy(), np.arange(n)), "frame_index must cover every frame in order"
    assert np.allclose(df['timestamp_sec'].to_numpy(dtype=float), np.arange(n) / 30.0,
                       rtol=0, atol=1e-6), "Timestamps must be frame_index / 30"

    actual = df['visibility_score'].to_numpy(dtype=float)
    err = np.abs(actual - expected_scores)
    assert float(err.mean()) < 0.005 and float(err.max()) < 0.02, \
        f"Visibility scores do not match model inference (mean error {err.mean():.6g}, max {err.max():.6g})"
    if np.std(expected_scores) > 1e-9:
        corr = float(np.corrcoef(actual, expected_scores)[0, 1])
        assert np.isfinite(corr) and corr > 0.995, f"Visibility scores do not track per-frame inference (correlation {corr})"


def test_merged_data_csv():
    path = "/home/user/merged_data.csv"
    assert os.path.isfile(path), f"Missing merged_data.csv at {path}"

    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "merged_data.csv is empty"
        rows = list(reader)
        assert len(rows) > 0, "merged_data.csv has no data rows"


def _nearest_values(source_times, source_values, target_time):
    distances = np.abs(source_times - target_time)
    minimum = distances.min()
    return source_values[np.isclose(distances, minimum, rtol=0, atol=1e-10)]


def test_merged_data_join_correctness():
    merged = pd.read_csv('/home/user/merged_data.csv')
    scores = pd.read_csv('/home/user/frame_scores.csv')
    telemetry = pd.read_csv('/app/data/telemetry.csv')
    gps = pd.read_csv('/app/data/gps.csv')

    required = ['frame_index', 'timestamp_sec', 'visibility_score', 'speed', 'lat', 'lon']
    for col in required:
        assert col in merged.columns, f"Column '{col}' missing from merged_data.csv"
    assert len(merged) == len(scores) == 300, "Merged output must contain exactly one row per video frame"
    assert not merged[required].isnull().any().any(), "Merged output contains missing joined values"
    for col in required:
        merged[col] = pd.to_numeric(merged[col], errors='raise')
    assert np.isfinite(merged[required].to_numpy(dtype=float)).all()

    merged = merged.sort_values('frame_index').reset_index(drop=True)
    scores = scores.sort_values('frame_index').reset_index(drop=True)
    assert np.array_equal(merged['frame_index'].to_numpy(), np.arange(300))
    assert np.allclose(merged['timestamp_sec'], scores['timestamp_sec'], rtol=0, atol=1e-8)
    assert np.allclose(merged['visibility_score'], scores['visibility_score'], rtol=0, atol=1e-7)

    tel_t = telemetry['timestamp_sec'].to_numpy(dtype=float)
    tel_v = telemetry['speed'].to_numpy(dtype=float)
    gps_t = gps['timestamp_sec'].to_numpy(dtype=float)
    lat_v = gps['lat'].to_numpy(dtype=float)
    lon_v = gps['lon'].to_numpy(dtype=float)

    for row in merged.itertuples(index=False):
        t = float(row.timestamp_sec)
        valid_speed = _nearest_values(tel_t, tel_v, t)
        assert np.any(np.isclose(float(row.speed), valid_speed, rtol=1e-7, atol=1e-10)), \
            f"Incorrect nearest telemetry join at timestamp {t}"

        distances = np.abs(gps_t - t)
        nearest = np.flatnonzero(np.isclose(distances, distances.min(), rtol=0, atol=1e-10))
        assert any(np.isclose(float(row.lat), lat_v[i], rtol=1e-7, atol=1e-10) and
                   np.isclose(float(row.lon), lon_v[i], rtol=1e-7, atol=1e-10)
                   for i in nearest), f"Incorrect nearest GPS join at timestamp {t}"


def _run_fixed_corpus(directory, expected_status):
    script_path = "/home/user/filter_plots.py"
    assert os.path.isfile(script_path), f"Missing filter_plots.py at {script_path}"
    assert os.path.isdir(directory), f"Corpus directory missing: {directory}"
    expected_files = {f for f in os.listdir(directory) if f.endswith('.png')}
    assert expected_files, f"No PNG files found in {directory}"

    result = subprocess.run(["python3", script_path, directory], capture_output=True, text=True)
    assert result.returncode == 0, f"filter_plots.py failed:\n{result.stderr}"
    processed_files = set()
    wrong_files = []
    for line in [x.strip() for x in result.stdout.splitlines() if x.strip()]:
        if ": " not in line:
            continue
        filename, status = line.split(": ", 1)
        if filename in expected_files:
            processed_files.add(filename)
            if status != expected_status:
                wrong_files.append(filename)
    missing_files = expected_files - processed_files
    assert not missing_files, f"filter_plots.py did not output status for: {missing_files}"
    assert not wrong_files, f"Files received the wrong classification: {wrong_files}"


def test_filter_plots_clean_corpus():
    _run_fixed_corpus('/app/verifier/clean/', 'ACCEPT')


def test_filter_plots_evil_corpus():
    _run_fixed_corpus('/app/verifier/evil/', 'REJECT')


def test_filter_plots_runtime_generated_mixed_corpus():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from PIL import Image

    script_path = '/home/user/filter_plots.py'
    assert os.path.isfile(script_path)
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))

    with tempfile.TemporaryDirectory(prefix='plot_validation_') as directory:
        expected = {}

        def name():
            return uuid.uuid4().hex + '.png'

        # Valid plots with runtime-randomized data, styling, and filenames.
        p = name()
        x = np.linspace(0, 8, 90)
        y = np.sin(x * rng.uniform(0.7, 1.8)) + rng.normal(0, 0.04, len(x))
        fig, ax = plt.subplots(figsize=(rng.uniform(4, 7), rng.uniform(3, 5)))
        ax.plot(x, y, color=rng.choice(['red', 'blue', 'green', 'purple']), linewidth=rng.uniform(1.2, 3.0))
        ax.set_title(uuid.uuid4().hex[:8])
        fig.savefig(os.path.join(directory, p))
        plt.close(fig)
        expected[p] = 'ACCEPT'

        p = name()
        x = rng.normal(size=70)
        y = 0.7 * x + rng.normal(scale=0.35, size=70)
        fig, ax = plt.subplots(figsize=(5.3, 3.7))
        ax.scatter(x, y, s=25, color='tab:orange')
        ax.set_xlabel('measurement')
        fig.savefig(os.path.join(directory, p))
        plt.close(fig)
        expected[p] = 'ACCEPT'

        # Blank axes, including randomized limits and dimensions.
        for _ in range(2):
            p = name()
            fig, ax = plt.subplots(figsize=(rng.uniform(4, 7), rng.uniform(3, 5)))
            ax.set_xlim(float(rng.uniform(-10, -1)), float(rng.uniform(1, 10)))
            ax.set_ylim(float(rng.uniform(-10, -1)), float(rng.uniform(1, 10)))
            ax.set_title(uuid.uuid4().hex[:6])
            fig.savefig(os.path.join(directory, p))
            plt.close(fig)
            expected[p] = 'REJECT'

        # Runtime-created solid images with unpredictable names, sizes, and gray level.
        for level in [0, 255, int(rng.integers(35, 220))]:
            p = name()
            size = (int(rng.integers(90, 180)), int(rng.integers(90, 180)))
            Image.new('RGB', size, color=(level, level, level)).save(os.path.join(directory, p))
            expected[p] = 'REJECT'

        result = subprocess.run(['python3', script_path, directory], capture_output=True, text=True)
        assert result.returncode == 0, f"filter_plots.py failed on generated corpus:\n{result.stderr}"
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        observed = {}
        for line in lines:
            assert line.count(': ') == 1, f"Invalid output format: {line!r}"
            filename, status = line.split(': ', 1)
            assert filename in expected, f"Unexpected filename in output: {filename!r}"
            assert status in {'ACCEPT', 'REJECT'}, f"Invalid status: {status!r}"
            assert filename not in observed, f"Duplicate output for {filename}"
            observed[filename] = status
        assert observed.keys() == expected.keys(), f"Missing classifications: {set(expected) - set(observed)}"
        wrong = {f: (observed[f], status) for f, status in expected.items() if observed[f] != status}
        assert not wrong, f"Incorrect generated-corpus classifications: {wrong}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
