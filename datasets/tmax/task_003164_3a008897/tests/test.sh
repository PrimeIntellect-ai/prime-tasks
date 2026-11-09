#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

import pytest
import requests
from PIL import Image
import numpy as np

_REFERENCE_DIR = None


def get_image_features(image_path):
    with Image.open(image_path) as img:
        arr = np.array(img.convert("RGB"))
    r = arr[:, :, 0]
    g = arr[:, :, 1]
    b = arr[:, :, 2]
    return [
        float(np.mean(r)),
        float(np.mean(g)),
        float(np.mean(b)),
        float(np.std(r)),
        float(np.std(g)),
        float(np.std(b)),
    ]


def get_reference_dir():
    global _REFERENCE_DIR
    if _REFERENCE_DIR is None:
        assert os.path.isfile("/app/test_video.mp4"), "Missing /app/test_video.mp4"
        _REFERENCE_DIR = tempfile.mkdtemp(prefix="reference_frames_")
        output_pattern = os.path.join(_REFERENCE_DIR, "frame_%d.png")
        result = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", "/app/test_video.mp4", "-vf", "fps=1", output_pattern,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Reference ffmpeg extraction failed: {result.stderr}"
    return _REFERENCE_DIR


def validate_and_get_reference_frames():
    frames_dir = "/home/user/frames"
    assert os.path.exists(frames_dir), f"Directory {frames_dir} does not exist."
    assert os.path.isdir(frames_dir), f"{frames_dir} is not a directory."

    reference_dir = get_reference_dir()
    pattern = re.compile(r"^frame_(\d+)\.png$")
    reference_files = sorted(
        (f for f in os.listdir(reference_dir) if pattern.match(f)),
        key=lambda f: int(pattern.match(f).group(1)),
    )
    submitted_files = sorted(
        (f for f in os.listdir(frames_dir) if pattern.match(f)),
        key=lambda f: int(pattern.match(f).group(1)),
    )

    assert len(submitted_files) > 0, "No frames extracted."
    assert len(reference_files) > 0, "The source video produced no 1-fps frames."
    assert submitted_files == reference_files, (
        f"Expected exactly {reference_files}, got {submitted_files}"
    )

    for filename in reference_files:
        submitted_path = os.path.join(frames_dir, filename)
        reference_path = os.path.join(reference_dir, filename)
        assert os.path.exists(submitted_path), f"Missing {submitted_path}"
        with Image.open(reference_path) as expected_img:
            expected = np.array(expected_img.convert("RGB"))
        with Image.open(submitted_path) as actual_img:
            assert actual_img.format == "PNG", f"{submitted_path} is not a PNG image"
            actual = np.array(actual_img.convert("RGB"))
        assert actual.shape == expected.shape, f"Incorrect dimensions for {filename}"
        assert np.array_equal(actual, expected), (
            f"{filename} does not match the frame extracted from /app/test_video.mp4 at 1 fps"
        )

    return reference_dir, len(reference_files)


def get_expected_data():
    reference_dir, N = validate_and_get_reference_frames()

    features = {}
    for i in range(1, N + 1):
        frame_path = os.path.join(reference_dir, f"frame_{i}.png")
        assert os.path.exists(frame_path), f"Missing reference frame {frame_path}"
        features[i] = get_image_features(frame_path)

    train_n = N // 2
    assert train_n > 0, "Not enough frames for a train split."
    train_features = [features[i] for i in range(1, train_n + 1)]

    train_means = []
    train_stds = []
    for col in range(6):
        col_vals = [f[col] for f in train_features]
        mean_val = sum(col_vals) / len(col_vals)
        train_means.append(mean_val)
        variance = sum((x - mean_val) ** 2 for x in col_vals) / len(col_vals)
        train_stds.append(math.sqrt(variance))

    scaled_features = {}
    for i in range(1, N + 1):
        scaled = []
        for col in range(6):
            std = train_stds[col] if train_stds[col] > 0 else 1.0
            scaled.append((features[i][col] - train_means[col]) / std)
        scaled_features[i] = scaled

    return N, train_means, scaled_features


def test_stats_endpoint():
    N, train_means, _ = get_expected_data()
    assert N >= 4, "At least four frames are required for top-3 recommendations."
    expected_means_rounded = [round(m, 2) for m in train_means]

    try:
        response = requests.get("http://127.0.0.1:8080/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /stats endpoint: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "train_means" in data, "Missing 'train_means' in response"
    actual_means = data["train_means"]
    assert len(actual_means) == 6, f"Expected 6 means, got {len(actual_means)}"

    for i, (expected, actual) in enumerate(zip(expected_means_rounded, actual_means)):
        assert math.isclose(expected, actual, abs_tol=0.05), (
            f"Mean {i} mismatch: expected ~{expected}, got {actual}"
        )


def test_recommend_endpoint():
    N, _, scaled_features = get_expected_data()

    # Exercise every valid frame ID, including the original fixed query frame_id=2.
    for target_id in range(1, N + 1):
        target_feats = scaled_features[target_id]
        distances = []
        for i in range(1, N + 1):
            if i == target_id:
                continue
            feats = scaled_features[i]
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(target_feats, feats)))
            distances.append((dist, i))

        distances.sort()
        expected_recommendations = [i for _, i in distances[:3]]

        try:
            response = requests.get(
                f"http://127.0.0.1:8080/recommend?frame_id={target_id}", timeout=5
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to /recommend endpoint: {e}")

        assert response.status_code == 200, (
            f"Expected status 200 for frame {target_id}, got {response.status_code}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail("Response is not valid JSON")

        assert "recommendations" in data, "Missing 'recommendations' in response"
        actual_recommendations = data["recommendations"]
        assert actual_recommendations == expected_recommendations, (
            f"For frame {target_id}, expected recommendations "
            f"{expected_recommendations}, got {actual_recommendations}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
