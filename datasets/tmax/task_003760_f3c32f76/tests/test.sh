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
import ast
import hashlib
import json
import math
import os
import shutil
import socket
import subprocess

import cv2
import numpy as np
import pytest
import requests

PIPELINE_PATH = "/home/user/pipeline.py"
PLOT_SCRIPT_PATH = "/home/user/generate_plot.py"
MSE_RESULTS_PATH = "/home/user/mse_results.json"
PLOT_IMAGE_PATH = "/home/user/motion_plot.png"
VIDEO_PATH = "/app/video_sample.mp4"
PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def compute_expected_mse(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video {path}."
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame.astype(np.float64).mean(axis=2))
    cap.release()
    assert len(frames) >= 2, "Video must contain at least two decoded frames."
    return [float(np.mean((frames[i] - frames[i - 1]) ** 2)) for i in range(1, len(frames))]


def load_results():
    with open(MSE_RESULTS_PATH, "r") as f:
        return json.load(f)


def assert_results_match(expected):
    data = load_results()
    assert isinstance(data, list), f"Expected a list in {MSE_RESULTS_PATH}."
    assert len(data) == len(expected), (
        f"Expected {len(expected)} consecutive-frame MSE values, got {len(data)}."
    )
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in data), (
        f"List in {MSE_RESULTS_PATH} must contain numeric values."
    )
    assert all(math.isfinite(float(x)) for x in data), "MSE values must be finite."
    assert np.allclose(np.asarray(data, dtype=float), np.asarray(expected), rtol=1e-7, atol=1e-4), (
        "MSE values do not match grayscale consecutive-frame MSE values recomputed from the video."
    )


def run_pipeline():
    subprocess.run(
        ["python3", PIPELINE_PATH],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def run_plot():
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    subprocess.run(
        ["python3", PLOT_SCRIPT_PATH],
        check=True,
        timeout=30,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def assert_valid_nonblank_png(path):
    assert os.path.exists(path), f"File {path} does not exist."
    size = os.path.getsize(path)
    assert size > 1000, f"File {path} seems too small to be a valid plot (size: {size} bytes)."
    with open(path, "rb") as f:
        header = f.read(8)
    assert header == PNG_HEADER, f"File {path} is not a valid PNG image."
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    assert image is not None and image.size > 0, f"File {path} could not be decoded as a PNG."
    assert float(np.std(image)) > 1.0 and int(image.max()) - int(image.min()) > 10, (
        f"File {path} appears blank."
    )


def test_pipeline_exists_executes_and_handles_video_frames():
    assert os.path.isfile(PIPELINE_PATH), f"File {PIPELINE_PATH} does not exist or is not a regular file."

    backup = "/tmp/video_sample_original.mp4"
    generated = "/tmp/verifier_video.mp4"
    shutil.copy2(VIDEO_PATH, backup)

    writer = cv2.VideoWriter(generated, cv2.VideoWriter_fourcc(*"mp4v"), 7.0, (64, 48))
    assert writer.isOpened(), "Could not create verifier test video."
    rng = np.random.default_rng(918273)
    for i in range(8):
        frame = np.zeros((48, 64, 3), dtype=np.uint8)
        frame[:] = (10 + i * 7, 25 + i * 3, 40 + i * 5)
        x = 3 + i * 5
        cv2.rectangle(frame, (x, 8), (min(x + 15, 63), 28), (220, 35 + i * 8, 90), -1)
        noise = rng.integers(0, 9, size=frame.shape, dtype=np.uint8)
        frame = cv2.add(frame, noise)
        writer.write(frame)
    writer.release()
    assert os.path.getsize(generated) > 0, "Verifier test video was not created."

    try:
        os.replace(generated, VIDEO_PATH)
        expected = compute_expected_mse(VIDEO_PATH)
        run_pipeline()
        assert_results_match(expected)
    finally:
        shutil.copy2(backup, VIDEO_PATH)
        run_pipeline()


def test_mse_results_exist_and_valid():
    assert os.path.exists(MSE_RESULTS_PATH), f"File {MSE_RESULTS_PATH} does not exist."
    with open(MSE_RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MSE_RESULTS_PATH} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected a list in {MSE_RESULTS_PATH}."
    assert len(data) > 0, f"List in {MSE_RESULTS_PATH} is empty."
    assert all(isinstance(x, (int, float)) for x in data), f"List in {MSE_RESULTS_PATH} must contain floats."
    assert_results_match(compute_expected_mse(VIDEO_PATH))


def test_plot_image_exists_and_valid():
    assert os.path.isfile(PLOT_SCRIPT_PATH), f"File {PLOT_SCRIPT_PATH} does not exist or is not a regular file."
    with open(PLOT_SCRIPT_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=PLOT_SCRIPT_PATH)
    gui_show_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "show"
    ]
    assert not gui_show_calls, "generate_plot.py must not call a GUI show() method."

    actual_data = load_results()
    first_hash = None
    second_hash = None
    try:
        with open(MSE_RESULTS_PATH, "w") as f:
            json.dump([0.0, 1.0, 4.0, 9.0, 16.0], f)
        run_plot()
        assert_valid_nonblank_png(PLOT_IMAGE_PATH)
        with open(PLOT_IMAGE_PATH, "rb") as f:
            first_hash = hashlib.sha256(f.read()).digest()

        with open(MSE_RESULTS_PATH, "w") as f:
            json.dump([16.0, 9.0, 4.0, 1.0, 0.0], f)
        run_plot()
        assert_valid_nonblank_png(PLOT_IMAGE_PATH)
        with open(PLOT_IMAGE_PATH, "rb") as f:
            second_hash = hashlib.sha256(f.read()).digest()
    finally:
        with open(MSE_RESULTS_PATH, "w") as f:
            json.dump(actual_data, f)
        run_plot()

    assert first_hash != second_hash, "The generated plot does not change when the MSE data changes."
    assert_valid_nonblank_png(PLOT_IMAGE_PATH)


def test_http_service():
    with open(MSE_RESULTS_PATH, "r") as f:
        data = json.load(f)

    max_val = max(data)
    max_idx = data.index(max_val) + 1

    try:
        response = requests.get("http://127.0.0.1:8080/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP GET to /stats failed: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        resp_json = response.json()
    except json.JSONDecodeError:
        pytest.fail("HTTP response body is not valid JSON.")

    assert "max_mse_frame" in resp_json, "Missing 'max_mse_frame' in HTTP response."
    assert "max_mse_value" in resp_json, "Missing 'max_mse_value' in HTTP response."
    assert resp_json["max_mse_frame"] == max_idx, f"Expected max_mse_frame to be {max_idx}, got {resp_json['max_mse_frame']}"
    assert abs(resp_json["max_mse_value"] - max_val) < 1e-4, f"Expected max_mse_value to be {max_val}, got {resp_json['max_mse_value']}"


def test_tcp_service():
    with open(PLOT_IMAGE_PATH, "rb") as f:
        expected_data = f.read()

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(("127.0.0.1", 9090))
        s.sendall(b"PLOT\n")
        received_data = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            received_data += chunk
        s.close()
    except Exception as e:
        pytest.fail(f"TCP connection or data transfer failed: {e}")

    assert received_data == expected_data, "Data received from TCP service does not match the contents of motion_plot.png."
    assert received_data.startswith(PNG_HEADER), "Received data is not a valid PNG."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
