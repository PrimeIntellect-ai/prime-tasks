#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import tempfile

import cv2
import numpy as np
import requests

URL = "http://127.0.0.1:8080/analyze_mesh"
VIDEO = "/app/aero_mesh_sim.mp4"
BASELINE = "/app/baseline_freqs.json"
REGIONS = [
    (0, 0, 100, 100),
    (100, 100, 200, 200),
    (200, 200, 300, 300),
]


def post(payload, timeout=15):
    try:
        response = requests.post(URL, json=payload, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the service at {URL}. Is it running? Error: {exc}"
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"
    assert "dominant_frequency" in data, "Missing 'dominant_frequency' in response"
    assert "is_divergent" in data, "Missing 'is_divergent' in response"
    return data


def payload(region):
    x_min, y_min, x_max, y_max = region
    return {
        "x_min": x_min,
        "y_min": y_min,
        "x_max": x_max,
        "y_max": y_max,
    }


def measured_frequencies(path):
    signals = [[] for _ in REGIONS]
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open generated probe video {path}"
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        for i, (x_min, y_min, x_max, y_max) in enumerate(REGIONS):
            signals[i].append(float(gray[y_min:y_max, x_min:x_max].mean()))
    cap.release()
    assert len(signals[0]) == 300, f"Expected 300 frames, decoded {len(signals[0])}"

    answers = []
    for signal in signals:
        values = np.asarray(signal, dtype=np.float64)
        spectrum = np.abs(np.fft.rfft(values))
        spectrum[0] = 0.0
        bins = np.fft.rfftfreq(values.size, d=1.0 / 30.0)
        answers.append(float(bins[int(np.argmax(spectrum))]))
    return answers


def write_random_probe_video(path):
    rng = secrets.SystemRandom()
    frequencies = rng.sample([1.3, 3.7, 6.8, 8.4, 11.6, 13.2], 3)
    phases = [rng.random() * 2.0 * np.pi for _ in REGIONS]
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(path, fourcc, 30, (400, 400), False)
    assert writer.isOpened(), "Could not create randomized probe video"
    for frame_number in range(300):
        t = frame_number / 30.0
        frame = np.zeros((400, 400), dtype=np.uint8)
        for region, frequency, phase in zip(REGIONS, frequencies, phases):
            x_min, y_min, x_max, y_max = region
            value = int(127 * np.sin(2 * np.pi * frequency * t + phase) + 128)
            frame[y_min:y_max, x_min:x_max] = value
        writer.write(frame)
    writer.release()


def test_service_ready_file():
    assert os.path.isfile("/home/user/service_ready.txt"), (
        "/home/user/service_ready.txt does not exist. Did you create it after starting the server?"
    )


def test_analyze_mesh_endpoint_original_cases():
    # Preserve the original verifier's three behavioral assertions.
    data1 = post(payload(REGIONS[0]))
    assert abs(data1["dominant_frequency"] - 2.0) < 0.1, (
        f"Expected dominant_frequency ~2.0, got {data1['dominant_frequency']}"
    )
    assert data1["is_divergent"] is False, (
        f"Expected is_divergent to be False, got {data1['is_divergent']}"
    )

    data2 = post(payload(REGIONS[1]))
    assert abs(data2["dominant_frequency"] - 5.0) < 0.1, (
        f"Expected dominant_frequency ~5.0, got {data2['dominant_frequency']}"
    )
    assert data2["is_divergent"] is True, (
        f"Expected is_divergent to be True, got {data2['is_divergent']}"
    )

    data3 = post(payload(REGIONS[2]))
    assert abs(data3["dominant_frequency"] - 10.0) < 0.1, (
        f"Expected dominant_frequency ~10.0, got {data3['dominant_frequency']}"
    )
    assert data3["is_divergent"] is False, (
        f"Expected is_divergent to be False, got {data3['is_divergent']}"
    )


def test_service_actually_analyzes_video():
    # Replace the video with an unpredictable probe after the original checks.
    # Expected answers are independently derived from the encoded/decoded probe.
    backup_fd, backup_path = tempfile.mkstemp(prefix="original_mesh_", suffix=".mp4")
    os.close(backup_fd)
    probe_fd, probe_path = tempfile.mkstemp(prefix="probe_mesh_", suffix=".mp4")
    os.close(probe_fd)
    shutil.copy2(VIDEO, backup_path)
    try:
        write_random_probe_video(probe_path)
        expected = measured_frequencies(probe_path)
        os.replace(probe_path, VIDEO)

        with open(BASELINE, "r", encoding="utf-8") as handle:
            baselines = json.load(handle)

        for region, expected_frequency in zip(REGIONS, expected):
            data = post(payload(region), timeout=30)
            assert isinstance(data["dominant_frequency"], (int, float)), (
                "dominant_frequency must be numeric"
            )
            assert isinstance(data["is_divergent"], bool), "is_divergent must be boolean"
            assert abs(float(data["dominant_frequency"]) - expected_frequency) < 0.11, (
                f"Expected FFT-derived frequency ~{expected_frequency}, "
                f"got {data['dominant_frequency']} for region {region}"
            )
            key = ",".join(str(v) for v in region)
            expected_divergent = abs(expected_frequency - float(baselines[key])) > 0.05
            assert data["is_divergent"] is expected_divergent, (
                f"Expected is_divergent={expected_divergent}, "
                f"got {data['is_divergent']} for region {region}"
            )
    finally:
        if os.path.exists(backup_path):
            os.replace(backup_path, VIDEO)
        if os.path.exists(probe_path):
            os.unlink(probe_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
