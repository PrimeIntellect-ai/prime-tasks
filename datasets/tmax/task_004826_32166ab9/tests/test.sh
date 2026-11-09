#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import subprocess
import time

import numpy as np
import pytest
import requests

API_BASE_URL = "http://127.0.0.1:8080"
VIDEO_PATH = "/app/security_feed.mp4"
CSV_PATH = "/home/user/sensor_logs.csv"


def get_json(endpoint):
    try:
        response = requests.get(f"{API_BASE_URL}{endpoint}", timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        pytest.fail(f"Failed to fetch {endpoint} from API: {e}")


@pytest.fixture(scope="session")
def reference_results():
    assert os.path.isfile(VIDEO_PATH), f"Video file missing at {VIDEO_PATH}"

    width, height = 640, 480
    frame_bytes = width * height
    command = [
        "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
        "-vf", "fps=1,format=gray", "-f", "rawvideo", "-pix_fmt", "gray", "-"
    ]

    started = time.perf_counter()
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    raw = result.stdout
    assert len(raw) % frame_bytes == 0, "ffmpeg returned incomplete grayscale frames"
    frame_count = len(raw) // frame_bytes
    assert frame_count == 60, f"Expected 60 one-frame-per-second samples, got {frame_count}"

    frames = np.frombuffer(raw, dtype=np.uint8).reshape(frame_count, height, width)
    scores = []
    for frame in frames:
        singular_values = np.linalg.svd(frame.astype(np.float64), compute_uv=False)
        scores.append(float(np.sum(singular_values[:10])))
    elapsed = time.perf_counter() - started
    scores = np.asarray(scores, dtype=np.float64)

    # A large deterministic bootstrap provides an independent estimate. The API's
    # required 1000-resample estimate is allowed normal Monte Carlo variation.
    rng = np.random.default_rng(917263)
    bootstrap_means = rng.choice(scores, size=(20000, frame_count), replace=True).mean(axis=1)
    lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])

    return {
        "scores": scores,
        "lower": float(lower),
        "upper": float(upper),
        "mean_inference_sec": elapsed / frame_count,
    }


def test_api_stats():
    data = get_json("/stats")

    assert "lower_bound" in data, "Missing 'lower_bound' in /stats response"
    assert "upper_bound" in data, "Missing 'upper_bound' in /stats response"
    assert "mean_inference_sec" in data, "Missing 'mean_inference_sec' in /stats response"

    lower_bound = float(data["lower_bound"])
    upper_bound = float(data["upper_bound"])
    mean_inference_sec = float(data["mean_inference_sec"])

    assert np.isfinite(lower_bound) and np.isfinite(upper_bound), "Confidence bounds must be finite"
    assert np.isfinite(mean_inference_sec), "Mean inference time must be finite"
    assert upper_bound > lower_bound, f"Upper bound ({upper_bound}) must be greater than lower bound ({lower_bound})"
    assert mean_inference_sec > 0, "Mean inference time must be positive"


def test_api_anomalies():
    data = get_json("/anomalies")

    assert "anomalous_frames" in data, "Missing 'anomalous_frames' in /anomalies response"
    anomalous_frames = data["anomalous_frames"]

    assert isinstance(anomalous_frames, list), "'anomalous_frames' must be a list"
    for frame in anomalous_frames:
        assert isinstance(frame, int) and not isinstance(frame, bool), "All items in 'anomalous_frames' must be integers"


def test_api_validation():
    anomalies_data = get_json("/anomalies")
    anomalous_frames = anomalies_data.get("anomalous_frames", [])

    validation_data = get_json("/validation")
    assert "precision" in validation_data, "Missing 'precision' in /validation response"
    reported_precision = float(validation_data["precision"])

    assert os.path.isfile(CSV_PATH), f"CSV file missing at {CSV_PATH}"

    sensor_active_map = {}
    with open(CSV_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensor_active_map[int(row["timestamp_sec"])] = int(row["sensor_active"])

    if not anomalous_frames:
        expected_precision = 0.0
    else:
        true_positives = sum(1 for frame in anomalous_frames if sensor_active_map.get(frame, 0) == 1)
        expected_precision = true_positives / len(anomalous_frames)

    assert np.isfinite(reported_precision), "Precision must be finite"
    assert 0.0 <= reported_precision <= 1.0, "Precision must be between 0.0 and 1.0"
    assert abs(reported_precision - expected_precision) < 1e-4, \
        f"Reported precision {reported_precision} does not match expected precision {expected_precision} based on returned anomalies."


def test_results_match_video_processing(reference_results):
    stats = get_json("/stats")
    anomalies_data = get_json("/anomalies")

    reported_lower = float(stats["lower_bound"])
    reported_upper = float(stats["upper_bound"])
    reported_time = float(stats["mean_inference_sec"])
    reported_anomalies = anomalies_data["anomalous_frames"]

    assert reported_lower > 0 and reported_upper > 0, "SVD complexity confidence bounds must be positive"
    assert len(reported_anomalies) == len(set(reported_anomalies)), "Anomaly indices must not contain duplicates"
    assert all(0 <= frame < len(reference_results["scores"]) for frame in reported_anomalies), \
        "Anomaly indices must correspond to extracted one-second video frames"

    ref_lower = reference_results["lower"]
    ref_upper = reference_results["upper"]
    ref_mid = (ref_lower + ref_upper) / 2.0
    ref_width = ref_upper - ref_lower
    reported_mid = (reported_lower + reported_upper) / 2.0

    # Pixel matrices may legitimately be represented on either a 0..255 or 0..1
    # scale. Fit that single scale factor, then verify the independently computed
    # bootstrap interval's location and width.
    scale = reported_mid / ref_mid
    tolerance = max(scale * 0.20 * ref_width, scale * 0.0005 * ref_mid)
    assert abs(reported_lower - scale * ref_lower) <= tolerance, \
        "Reported lower bound is inconsistent with a 1000-resample bootstrap of the video SVD scores"
    assert abs(reported_upper - scale * ref_upper) <= tolerance, \
        "Reported upper bound is inconsistent with a 1000-resample bootstrap of the video SVD scores"

    # Permit frames close enough to the percentile to change classification due
    # to bootstrap randomness, but require all clear anomalies and reject clear
    # non-anomalies.
    anomaly_margin = max(0.20 * ref_width, 0.0005 * ref_mid)
    definitely_anomalous = {
        i for i, score in enumerate(reference_results["scores"])
        if score > ref_upper + anomaly_margin
    }
    definitely_normal = {
        i for i, score in enumerate(reference_results["scores"])
        if score <= ref_upper - anomaly_margin
    }
    returned = set(reported_anomalies)
    assert definitely_anomalous <= returned, \
        f"Missing anomalies required by independently computed video scores: {sorted(definitely_anomalous - returned)}"
    assert returned.isdisjoint(definitely_normal), \
        f"Returned frames that are below the independently computed anomaly threshold: {sorted(returned & definitely_normal)}"

    reference_time = reference_results["mean_inference_sec"]
    assert reference_time * 0.02 <= reported_time <= reference_time * 20.0, \
        f"Reported per-frame processing time {reported_time} is implausible versus measured processing time {reference_time}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
