#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np
import pytest
import requests
from sklearn.linear_model import LogisticRegression

BASE_URL = "http://127.0.0.1:8000"
AUTH_HEADER = {"Authorization": "Bearer ml-data-token-999"}
VIDEO_PATH = "/app/sample_video.mp4"


def wait_for_service(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(BASE_URL, timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.25)
    return False


@pytest.fixture(scope="module", autouse=True)
def ensure_service_running():
    assert wait_for_service(), "FastAPI service is not running on 127.0.0.1:8000"


def assert_feature_schema(item):
    assert set(item) == {"frame_index", "mean_intensity", "is_bright"}
    assert type(item["frame_index"]) is int
    assert type(item["mean_intensity"]) is float
    assert type(item["is_bright"]) is bool


def assert_prediction_schema(data):
    assert set(data) == {"predicted_is_bright"}
    assert type(data["predicted_is_bright"]) is bool


def test_get_features_unauthorized():
    response = requests.get(f"{BASE_URL}/features")
    assert response.status_code in [401, 403]


def test_get_features_authorized():
    response = requests.get(f"{BASE_URL}/features", headers=AUTH_HEADER)
    assert response.status_code == 200, response.text
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 10
    for i in range(10):
        item = data[i]
        assert_feature_schema(item)
        assert item["frame_index"] == i
        if i < 5:
            assert not item["is_bright"]
            assert item["mean_intensity"] < 120.0
        else:
            assert item["is_bright"]
            assert item["mean_intensity"] >= 120.0


def test_post_predict_authorized_dark():
    response = requests.post(f"{BASE_URL}/predict", json={"frame_index": 2}, headers=AUTH_HEADER)
    assert response.status_code == 200, response.text
    data = response.json()
    assert_prediction_schema(data)
    assert data["predicted_is_bright"] is False


def test_post_predict_authorized_bright():
    response = requests.post(f"{BASE_URL}/predict", json={"frame_index": 8}, headers=AUTH_HEADER)
    assert response.status_code == 200, response.text
    data = response.json()
    assert_prediction_schema(data)
    assert data["predicted_is_bright"] is True


def test_post_predict_invalid_schema():
    response = requests.post(f"{BASE_URL}/predict", json={"frame": "two"}, headers=AUTH_HEADER)
    assert response.status_code == 422


def test_predict_authorization_and_strict_extra_fields():
    for headers in ({}, {"Authorization": "Bearer wrong-token"}):
        response = requests.post(f"{BASE_URL}/predict", json={"frame_index": 3}, headers=headers)
        assert response.status_code in [401, 403]
    response = requests.post(
        f"{BASE_URL}/predict",
        json={"frame_index": 3, "extra": "must be rejected"},
        headers=AUTH_HEADER,
    )
    assert response.status_code == 422, response.text


def listening_pid(port=8000):
    target = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == target and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                link = os.readlink(fd)
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            pass
    raise AssertionError("Could not identify the process listening on port 8000")


def process_launch_info(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    cmd = [part.decode() for part in raw if part]
    assert cmd, "API process has no restartable command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        env.update(
            entry.decode().split("=", 1)
            for entry in entries
            if entry and b"=" in entry
        )
    except (OSError, UnicodeDecodeError):
        pass
    return cmd, cwd, env


def stop_process(pid):
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    os.kill(pid, signal.SIGKILL)
    time.sleep(0.5)


def make_random_video(path):
    rng = random.SystemRandom()
    seconds = rng.randint(7, 13)
    dark = [rng.randint(15, 100) for _ in range(seconds // 2)]
    bright = [rng.randint(145, 235) for _ in range(seconds - len(dark))]
    levels = dark + bright
    rng.shuffle(levels)

    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 30, (160, 120))
    assert writer.isOpened(), "Unable to create randomized verification video"
    for level in levels:
        frame = np.full((120, 160, 3), level, dtype=np.uint8)
        for _ in range(30):
            writer.write(frame)
    writer.release()
    return seconds


def derive_features(path, count):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened()
    result = []
    for index in range(count):
        cap.set(cv2.CAP_PROP_POS_MSEC, index * 1000.0)
        ok, frame = cap.read()
        assert ok, f"Verifier could not decode timestamp {index}.0s"
        mean = float(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).mean())
        result.append({
            "frame_index": index,
            "mean_intensity": mean,
            "is_bright": mean >= 120.0,
        })
    cap.release()
    return result


def test_service_recomputes_randomized_video_and_uses_logistic_regression():
    pid = listening_pid()
    cmd, cwd, env = process_launch_info(pid)
    stop_process(pid)

    count = make_random_video(VIDEO_PATH)
    expected = derive_features(VIDEO_PATH, count)
    labels = [row["is_bright"] for row in expected]
    assert any(labels) and not all(labels)

    with open("/tmp/restarted_api.log", "wb") as log:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    assert wait_for_service(), "Submitted API did not restart after the input video changed"

    response = requests.get(f"{BASE_URL}/features", headers=AUTH_HEADER)
    assert response.status_code == 200, response.text
    actual = response.json()
    assert len(actual) == count
    for got, wanted in zip(actual, expected):
        assert_feature_schema(got)
        assert got["frame_index"] == wanted["frame_index"]
        assert abs(got["mean_intensity"] - wanted["mean_intensity"]) <= 0.05
        assert got["is_bright"] is wanted["is_bright"]

    model = LogisticRegression(random_state=42)
    model.fit(np.arange(count).reshape(-1, 1), np.asarray(labels, dtype=bool))
    query_indices = list(range(-5, count + 6))
    expected_predictions = model.predict(np.asarray(query_indices).reshape(-1, 1))
    for index, wanted in zip(query_indices, expected_predictions):
        response = requests.post(
            f"{BASE_URL}/predict",
            json={"frame_index": index},
            headers=AUTH_HEADER,
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert_prediction_schema(data)
        assert data["predicted_is_bright"] is bool(wanted)

    assert proc.poll() is None, "API process exited during verification"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
