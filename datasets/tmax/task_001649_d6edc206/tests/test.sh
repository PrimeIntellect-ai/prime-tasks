#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import runpy
import secrets
import shutil
import subprocess
from unittest import mock

import cv2
import matplotlib.axes
import matplotlib.figure
import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
VIDEO = "/app/experiment_feed.mp4"
SCRIPT = "/home/user/analyze.py"
JSON_PATH = "/home/user/tracking.json"
PLOT_PATH = "/home/user/bootstrap_dist.png"


def reference_results(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open {video_path}"
    fps = cap.get(cv2.CAP_PROP_FPS)
    assert np.isfinite(fps) and int(fps) > 0, f"Invalid video FPS: {fps}"
    interval = int(fps)
    intensities = []
    count = 0
    while cap.isOpened():
        ok, frame = cap.read()
        if not ok:
            break
        if count % interval == 0:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            intensities.append(float(np.mean(gray)))
        count += 1
    cap.release()
    assert intensities, "The supplied video yielded no sampled frames"

    values = np.asarray(intensities)
    rng = np.random.RandomState(42)
    means = np.asarray([
        np.mean(rng.choice(values, size=len(values), replace=True))
        for _ in range(1000)
    ])
    result = {
        "mean": float(np.mean(values)),
        "lower_bound": float(np.percentile(means, 2.5)),
        "upper_bound": float(np.percentile(means, 97.5)),
    }
    return result, means


def assert_tracking_file(expected):
    assert os.path.isfile(JSON_PATH), f"Expected tracking JSON at {JSON_PATH}"
    with open(JSON_PATH) as f:
        data = json.load(f)
    for key in ("mean", "lower_bound", "upper_bound"):
        assert key in data, f"tracking.json is missing {key}"
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool)
        assert np.isfinite(data[key]), f"{key} is not finite"
        assert data[key] == pytest.approx(expected[key], abs=1e-7, rel=1e-7), \
            f"Incorrect {key}: expected {expected[key]}, got {data[key]}"
    return data


def assert_plot_file():
    assert os.path.isfile(PLOT_PATH), f"Expected plot at {PLOT_PATH}"
    assert os.path.getsize(PLOT_PATH) > 1000, "Plot is empty or suspiciously small"
    with open(PLOT_PATH, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "Plot is not a PNG"
    image = cv2.imread(PLOT_PATH, cv2.IMREAD_COLOR)
    assert image is not None and image.size > 0, "Plot PNG cannot be decoded"
    assert np.unique(image.reshape(-1, 3), axis=0).shape[0] > 10, "Plot appears blank"


def create_challenge_video(path):
    rng = secrets.SystemRandom()
    levels = [rng.randrange(20, 236) for _ in range(7)]
    while max(levels) - min(levels) < 100:
        levels = [rng.randrange(20, 236) for _ in range(7)]

    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 10.0, (160, 120))
    assert writer.isOpened(), "Could not create verifier challenge video"
    x = np.arange(160, dtype=np.uint8)[None, :]
    y = np.arange(120, dtype=np.uint8)[:, None]
    for second, level in enumerate(levels):
        for frame_no in range(10):
            variation = ((x // 16 + y // 12 + second + frame_no) % 5).astype(np.int16) - 2
            gray = np.clip(level + variation, 0, 255).astype(np.uint8)
            frame = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
            writer.write(frame)
    writer.release()


@pytest.fixture(scope="session", autouse=True)
def execute_and_verify_analysis(tmp_path_factory):
    assert os.path.isfile(SCRIPT), f"Analysis script does not exist at {SCRIPT}"
    assert os.path.isfile(VIDEO), f"Experiment video does not exist at {VIDEO}"
    assert os.path.getsize(VIDEO) > 0, "Experiment video is empty"

    backup = tmp_path_factory.mktemp("video") / "experiment_feed.mp4"
    shutil.copy2(VIDEO, backup)

    try:
        create_challenge_video(VIDEO)
        expected, expected_means = reference_results(VIDEO)
        events = []
        plotted = []
        original_hist = matplotlib.axes.Axes.hist
        original_savefig = matplotlib.figure.Figure.savefig

        def recording_hist(self, values, *args, **kwargs):
            plotted.append(np.asarray(values, dtype=float).ravel().copy())
            events.append("hist")
            return original_hist(self, values, *args, **kwargs)

        def recording_savefig(self, *args, **kwargs):
            events.append("save")
            return original_savefig(self, *args, **kwargs)

        for path in (JSON_PATH, PLOT_PATH):
            if os.path.exists(path):
                os.remove(path)

        with mock.patch.object(matplotlib.axes.Axes, "hist", recording_hist), \
             mock.patch.object(matplotlib.figure.Figure, "savefig", recording_savefig):
            runpy.run_path(SCRIPT, run_name="__main__")

        assert plotted, "The analysis never plotted a histogram"
        assert any(len(values) == 1000 and np.allclose(
            np.sort(values), np.sort(expected_means), atol=1e-10, rtol=1e-10
        ) for values in plotted), "Histogram does not contain the computed 1000-sample bootstrap distribution"
        assert "save" in events and max(i for i, event in enumerate(events) if event == "save") > \
            min(i for i, event in enumerate(events) if event == "hist"), \
            "The figure was not saved after the histogram was plotted"
        assert_tracking_file(expected)
        assert_plot_file()
    finally:
        shutil.copy2(backup, VIDEO)

    completed = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert completed.returncode == 0, \
        f"analyze.py failed on the supplied video:\n{completed.stdout}\n{completed.stderr}"
    final_expected, _ = reference_results(VIDEO)
    assert_tracking_file(final_expected)
    assert_plot_file()
    return final_expected


def test_tracking_endpoint(execute_and_verify_analysis):
    url = f"{BASE_URL}/api/tracking"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {url}: {exc}")
    assert response.status_code == 200
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /api/tracking is not valid JSON")

    expected_keys = {"mean", "lower_bound", "upper_bound"}
    assert expected_keys.issubset(data.keys())
    for key in expected_keys:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool)
        assert data[key] == pytest.approx(execute_and_verify_analysis[key], abs=1e-7, rel=1e-7)

    with open(JSON_PATH) as f:
        local = json.load(f)
    for key in expected_keys:
        assert data[key] == pytest.approx(local[key], abs=1e-10, rel=1e-10)


def test_plot_endpoint():
    url = f"{BASE_URL}/api/plot"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {url}: {exc}")
    assert response.status_code == 200
    assert response.content.startswith(b"\x89PNG\r\n\x1a\n")
    with open(PLOT_PATH, "rb") as f:
        assert response.content == f.read(), "/api/plot did not serve the generated plot file"


def test_local_files_generated():
    assert_tracking_file(reference_results(VIDEO)[0])
    assert_plot_file()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
