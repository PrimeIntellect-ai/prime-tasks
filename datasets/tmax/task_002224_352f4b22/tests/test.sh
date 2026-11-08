#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets

import cv2
import numpy as np
import requests
from scipy.stats import ks_2samp, wasserstein_distance

VIDEO_PATH = "/app/rendering.mp4"


def load_frames():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).reshape(-1))
    cap.release()
    assert len(frames) >= 30, f"Expected at least 30 video frames, found {len(frames)}"
    return frames


FRAMES = load_frames()

# np.random.seed(42) uses RandomState. Also accept default_rng(42), since both are
# reasonable interpretations of using NumPy with the required fixed seed.
REFERENCE_SAMPLES = [
    np.random.RandomState(42).beta(2.0, 5.0, 100000) * 255.0,
    np.random.default_rng(42).beta(2.0, 5.0, 100000) * 255.0,
]


def expected_candidates(frame_index):
    pixels = FRAMES[frame_index]
    candidates = []
    for samples in REFERENCE_SAMPLES:
        w = float(wasserstein_distance(pixels, samples))
        p = float(ks_2samp(pixels, samples).pvalue)
        candidates.append((w, p, p > 0.01 and w < 10.0))
    return candidates


def verify_response_format(data, expected_frame):
    assert "frame" in data, "Response missing 'frame' key"
    assert "wasserstein" in data, "Response missing 'wasserstein' key"
    assert "p_value" in data, "Response missing 'p_value' key"
    assert "stable" in data, "Response missing 'stable' key"
    assert set(data) == {"frame", "wasserstein", "p_value", "stable"}, \
        f"Response must contain exactly the specified keys: {data}"

    assert data["frame"] == expected_frame, f"Expected frame {expected_frame}, got {data['frame']}"
    assert isinstance(data["wasserstein"], float), "wasserstein should be a float"
    assert isinstance(data["p_value"], float), "p_value should be a float"
    assert isinstance(data["stable"], bool), "stable should be a boolean"
    assert math.isfinite(data["wasserstein"]) and data["wasserstein"] >= 0.0
    assert math.isfinite(data["p_value"]) and 0.0 <= data["p_value"] <= 1.0


def query_and_verify(frame_index):
    try:
        response = requests.get(f"http://127.0.0.1:8080/profile/{frame_index}", timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the web service: {e}"

    assert response.status_code == 200, \
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    verify_response_format(data, frame_index)

    # Require the two reported statistics to be a matching pair computed from the
    # actual decoded frame and exactly 100,000 seed-42 Beta samples. Small
    # tolerances allow harmless grayscale-decoder rounding differences.
    matched = None
    for expected_w, expected_p, expected_stable in expected_candidates(frame_index):
        w_close = math.isclose(data["wasserstein"], expected_w, rel_tol=0.0, abs_tol=0.05)
        p_close = math.isclose(data["p_value"], expected_p, rel_tol=0.10, abs_tol=0.02)
        if w_close and p_close:
            matched = (expected_w, expected_p, expected_stable)
            break

    assert matched is not None, (
        f"Frame {frame_index} statistics do not match scipy calculations from the video. "
        f"Got wasserstein={data['wasserstein']}, p_value={data['p_value']}; "
        f"expected one of {[(w, p) for w, p, _ in expected_candidates(frame_index)]}"
    )
    assert data["stable"] == matched[2], \
        f"Stable flag does not follow the required thresholds for frame {frame_index}: {data}"
    assert data["stable"] == (data["p_value"] > 0.01 and data["wasserstein"] < 10.0), \
        f"Stable flag is inconsistent with the returned statistics: {data}"
    return data


def test_frame_0():
    data = query_and_verify(0)
    assert data["stable"] is False, f"Frame 0 is anomalous and should be unstable. Response: {data}"


def test_frame_5():
    data = query_and_verify(5)
    assert data["stable"] is True, f"Frame 5 is stable and should be true. Response: {data}"


def test_frame_10():
    data = query_and_verify(10)
    assert data["stable"] is False, f"Frame 10 is anomalous and should be unstable. Response: {data}"


def test_unpredictable_frames_against_video_and_scipy():
    population = [i for i in range(len(FRAMES)) if i not in {0, 5, 10}]
    for frame_index in secrets.SystemRandom().sample(population, min(6, len(population))):
        query_and_verify(frame_index)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
