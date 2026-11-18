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
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import math
import subprocess

import pytest
import requests

VIDEO = "/app/diagnostic_feed.mp4"


def extract_reference_frame(timestamp):
    proc = subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-i", VIDEO,
            "-ss", f"{timestamp:.9f}", "-frames:v", "1", "-an",
            "-f", "image2pipe", "-vcodec", "mjpeg", "pipe:1",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f"Reference ffmpeg failed: {proc.stderr.decode(errors='replace')}"
    assert proc.stdout.startswith(b'\xff\xd8\xff'), "Reference extraction did not produce JPEG data."
    return proc.stdout


def decode_jpeg_to_rgb(jpeg):
    proc = subprocess.run(
        [
            "ffmpeg", "-loglevel", "error", "-f", "image2pipe",
            "-i", "pipe:0", "-frames:v", "1", "-f", "rawvideo",
            "-pix_fmt", "rgb24", "pipe:1",
        ],
        input=jpeg,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f"JPEG could not be decoded by ffmpeg: {proc.stderr.decode(errors='replace')}"
    assert proc.stdout, "Decoded JPEG contained no image pixels."
    return proc.stdout


def test_service_extraction():
    url = "http://127.0.0.1:8080/extract"
    payload = {
        "video_path": VIDEO,
        "t0": 2.0,
        "delta": 1.0,
        "n": 4
    }

    try:
        resp = requests.post(url, json=payload, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service at {url}: {e}")

    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}. Response body: {resp.text}"

    try:
        data = resp.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON. Response body: {resp.text}")

    assert "frames" in data, "Response JSON is missing the 'frames' key."

    frames = data["frames"]
    assert isinstance(frames, list), f"Expected 'frames' to be a list, got {type(frames)}."
    assert len(frames) == 4, f"Expected exactly 4 frames, got {len(frames)}."

    timestamps = [payload["t0"] + i * i * payload["delta"] for i in range(payload["n"])]
    expected_pixels = [decode_jpeg_to_rgb(extract_reference_frame(t)) for t in timestamps]

    for i, b64_str in enumerate(frames):
        try:
            img_bytes = base64.b64decode(b64_str)
        except Exception as e:
            pytest.fail(f"Frame {i} is not a valid Base64 string: {e}")

        # Preserve the original JPEG shape and size assertions.
        assert img_bytes.startswith(b'\xff\xd8\xff'), f"Frame {i} is not a valid JPEG image (missing magic bytes)."
        assert len(img_bytes) > 1024, f"Frame {i} is too small ({len(img_bytes)} bytes) to be a valid captured frame."

        actual = decode_jpeg_to_rgb(img_bytes)
        expected = expected_pixels[i]
        assert len(actual) == len(expected), f"Frame {i} has incorrect image dimensions."

        absolute_error = sum(abs(a - b) for a, b in zip(actual, expected)) / len(expected)
        squared_error = sum((a - b) ** 2 for a, b in zip(actual, expected)) / len(expected)
        rmse = math.sqrt(squared_error)
        assert absolute_error < 6.0 and rmse < 14.0, (
            f"Frame {i} does not match the video frame at T_{i}={timestamps[i]}s "
            f"(mean absolute error={absolute_error:.3f}, RMSE={rmse:.3f})."
        )
TEST_EOF

reward=0

if (cd /home/user/workspace/vid_service && GO111MODULE=off go build -o /tmp/vid_service_verified main.go); then
    # Stop the agent-started listener so the verifier executes the submitted Go artifact itself.
    python3 << 'KILL_EOF'
import glob
import os
import signal

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for fd in glob.glob("/proc/[0-9]*/fd/*"):
    try:
        target = os.readlink(fd)
        if target.startswith("socket:[") and target[8:-1] in inodes:
            pid = int(fd.split("/")[2])
            if pid != os.getpid():
                os.kill(pid, signal.SIGKILL)
    except (OSError, ValueError, ProcessLookupError):
        pass
KILL_EOF

    sleep 1
    /tmp/vid_service_verified >/tmp/vid_service_verified.log 2>&1 &
    service_pid=$!
    sleep 1

    if kill -0 "$service_pid" 2>/dev/null && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        reward=1
    fi

    kill "$service_pid" 2>/dev/null || true
    wait "$service_pid" 2>/dev/null || true
fi

echo "$reward" > /logs/verifier/reward.txt
