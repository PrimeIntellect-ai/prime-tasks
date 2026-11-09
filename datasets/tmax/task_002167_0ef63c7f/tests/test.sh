#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

BASE_URL = "http://127.0.0.1:8080"
VIDEO = "/app/experiment_record.mp4"


def get_json(path, timeout=3):
    request = urllib.request.Request(BASE_URL + path, method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        assert response.status == 200, f"Expected 200 OK from {path}, got {response.status}"
        return json.loads(response.read().decode("utf-8"))


def wait_for_service(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            get_json("/anomalies", timeout=1)
            return True
        except Exception:
            time.sleep(0.5)
    return False


def pearson(a, b):
    n = len(a)
    ma = sum(a) / n
    mb = sum(b) / n
    numerator = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    da = sum((x - ma) ** 2 for x in a)
    db = sum((y - mb) ** 2 for y in b)
    assert da > 0 and db > 0, "Unexpected constant oracle frame"
    return numerator / math.sqrt(da * db)


def build_oracle():
    work = tempfile.mkdtemp(prefix="verifier_oracle_")
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", VIDEO, "-vf", "fps=1", "-start_number", "0",
        "-q:v", "2", os.path.join(work, "oracle_%02d.jpg")
    ], check=True)

    frame_paths = []
    i = 0
    while True:
        path = os.path.join(work, f"oracle_{i:02d}.jpg")
        if not os.path.isfile(path):
            break
        frame_paths.append(path)
        i += 1
    assert frame_paths, "Verifier could not extract oracle frames"

    embeddings = []
    for path in frame_paths:
        raw = subprocess.check_output([
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", path, "-vf", "format=gray,scale=32:32:flags=bilinear",
            "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gray", "-"
        ])
        assert len(raw) == 1024
        embeddings.append(list(raw))

    matrix = [[pearson(a, b) for b in embeddings] for a in embeddings]
    anomalies = [i for i in range(1, len(embeddings)) if matrix[i - 1][i] < 0.85]
    return work, embeddings, matrix, anomalies


ORACLE_DIR, EMBEDDINGS, EXPECTED_CORRELATIONS, EXPECTED_ANOMALIES = build_oracle()
FRAME_COUNT = len(EMBEDDINGS)


@pytest.fixture(scope="module", autouse=True)
def check_service_up():
    assert wait_for_service(), f"Service at {BASE_URL} did not start or is not reachable."


def find_extracted_frame_directory():
    required = {f"frame_{i:02d}.jpg" for i in range(FRAME_COUNT)}
    candidates = {}
    skip_dirs = {"proc", "sys", "dev", "run"}

    for root, dirs, files in os.walk("/", topdown=True):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        if os.path.abspath(root) == os.path.abspath(ORACLE_DIR):
            dirs[:] = []
            continue
        present = required.intersection(files)
        if present:
            candidates.setdefault(root, set()).update(present)

    complete = [directory for directory, names in candidates.items() if names == required]
    assert complete, (
        f"Could not find one directory containing all extracted frames "
        f"frame_00.jpg through frame_{FRAME_COUNT - 1:02d}.jpg"
    )
    return complete[0]


def test_extracted_frames_exist_and_are_decodable():
    directory = find_extracted_frame_directory()
    for i in range(FRAME_COUNT):
        path = os.path.join(directory, f"frame_{i:02d}.jpg")
        assert os.path.isfile(path), f"Missing extracted frame {path}"
        decoded = subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
            "-frames:v", "1", "-f", "null", "-"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert decoded.returncode == 0, f"Extracted frame is not a decodable image: {path}"


def test_anomalies_endpoint():
    data = get_json("/anomalies")
    assert "anomalies" in data, "Response JSON missing 'anomalies' key"
    anomalies = data["anomalies"]
    assert isinstance(anomalies, list), "'anomalies' should be a list"
    assert anomalies == [10, 20], f"Expected anomalies to be [10, 20], got {anomalies}"
    assert anomalies == EXPECTED_ANOMALIES, (
        f"Anomalies do not match correlations independently derived from the video: "
        f"expected {EXPECTED_ANOMALIES}, got {anomalies}"
    )


def read_correlation(f1, f2):
    data = get_json(f"/correlation?f1={f1}&f2={f2}")
    assert "correlation" in data, "Response JSON missing 'correlation' key"
    value = data["correlation"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool), (
        "'correlation' should be a number"
    )
    assert math.isfinite(value), "'correlation' must be finite"
    return float(value)


def test_correlation_endpoint_normal():
    corr = read_correlation(0, 1)
    assert corr >= 0.85, f"Expected correlation between frame 0 and 1 to be >= 0.85, got {corr}"


def test_correlation_endpoint_anomaly():
    corr = read_correlation(9, 10)
    assert corr < 0.85, f"Expected correlation between frame 9 and 10 to be < 0.85, got {corr}"


def test_all_frame_pair_correlations_against_video():
    # Exercise every valid frame pair, rather than trusting a fixed subset. A small
    # tolerance accommodates JPEG encoder and Pillow/ffmpeg bilinear implementation
    # differences while still requiring the actual per-pair correlation structure.
    for f1 in range(FRAME_COUNT):
        for f2 in range(FRAME_COUNT):
            actual = read_correlation(f1, f2)
            expected = round(EXPECTED_CORRELATIONS[f1][f2], 4)
            assert abs(actual - expected) <= 0.01, (
                f"Wrong correlation for frames {f1} and {f2}: "
                f"expected approximately {expected}, got {actual}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
