#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /app/test_feed.mp4 /tmp/verifier_original_feed.mp4
rm -f /tmp/verifier_ffmpeg_calls.jsonl
mv /usr/bin/ffmpeg /usr/bin/ffmpeg.real
cat <<'WRAPPER_EOF' > /usr/bin/ffmpeg
#!/usr/bin/python3
import fcntl
import hashlib
import json
import os
import subprocess
import sys

LOG = "/tmp/verifier_ffmpeg_calls.jsonl"
REAL = "/usr/bin/ffmpeg.real"
args = sys.argv[1:]
result = subprocess.run([REAL] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

hashes = []
if result.stdout:
    hashes.append({
        "source": "stdout",
        "length": len(result.stdout),
        "sha256": hashlib.sha256(result.stdout).hexdigest(),
    })

seen = set()
for arg in args:
    try:
        path = os.path.abspath(arg)
        if path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        with open(path, "rb") as f:
            content = f.read()
        hashes.append({
            "source": path,
            "length": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        })
    except (OSError, ValueError):
        pass

try:
    with open(LOG, "a", encoding="utf-8") as log:
        fcntl.flock(log.fileno(), fcntl.LOCK_EX)
        log.write(json.dumps({"argv": args, "returncode": result.returncode, "hashes": hashes}) + "\n")
        log.flush()
        fcntl.flock(log.fileno(), fcntl.LOCK_UN)
except OSError:
    pass

os.write(1, result.stdout)
os.write(2, result.stderr)
sys.exit(result.returncode)
WRAPPER_EOF
chmod 755 /usr/bin/ffmpeg

cleanup() {
    cp /tmp/verifier_original_feed.mp4 /app/test_feed.mp4 2>/dev/null || true
    rm -f /usr/bin/ffmpeg
    mv /usr/bin/ffmpeg.real /usr/bin/ffmpeg 2>/dev/null || true
}
trap cleanup EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import json
import os
import random
import subprocess
import zlib

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
VIDEO_PATH = "/app/test_feed.mp4"
FFMPEG_LOG = "/tmp/verifier_ffmpeg_calls.jsonl"


def get_expected_frame_bytes(frame_index_1_based):
    n_index = frame_index_1_based - 1
    cmd = [
        "ffmpeg",
        "-i", VIDEO_PATH,
        "-vf", f"select=eq(n\\,{n_index})",
        "-vframes", "1",
        "-pix_fmt", "gray",
        "-f", "image2pipe",
        "-vcodec", "rawvideo",
        "-",
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"ffmpeg failed: {result.stderr.decode()}"
    assert len(result.stdout) > 0, "ffmpeg returned empty raw bytes for the frame."
    return result.stdout


def get_expected_frame_data(frame_index_1_based):
    raw_bytes = get_expected_frame_bytes(frame_index_1_based)
    return zlib.crc32(raw_bytes), sum(raw_bytes)


def assert_analyze(frame):
    expected_crc, expected_luma = get_expected_frame_data(frame)
    try:
        response = requests.get(f"{BASE_URL}/analyze?frame={frame}", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /analyze?frame={frame}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type: application/json"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "frame" in data, "Missing 'frame' in response"
    assert "crc32" in data, "Missing 'crc32' in response"
    assert "luma_sum" in data, "Missing 'luma_sum' in response"
    assert data["frame"] == frame, f"Expected frame {frame}, got {data['frame']}"
    assert data["crc32"] == expected_crc, f"Expected crc32 {expected_crc}, got {data['crc32']}"
    assert data["luma_sum"] == expected_luma, f"Expected luma_sum {expected_luma}, got {data['luma_sum']}"


def test_analyze_frame_1():
    assert_analyze(1)


def test_analyze_frame_15():
    assert_analyze(15)


def test_analyze_unpredictable_video_frames():
    width, height, frame_count = 320, 240, 20
    raw_path = "/tmp/verifier_random_frames.gray"
    new_video = "/tmp/verifier_random_feed.mkv"
    with open(raw_path, "wb") as f:
        f.write(os.urandom(width * height * frame_count))

    result = subprocess.run([
        "ffmpeg", "-y",
        "-f", "rawvideo", "-pix_fmt", "gray",
        "-s", f"{width}x{height}", "-r", "10",
        "-i", raw_path,
        "-frames:v", str(frame_count),
        "-c:v", "ffv1", new_video,
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"Failed to create verifier video: {result.stderr.decode()}"
    os.replace(new_video, VIDEO_PATH)

    frames = random.SystemRandom().sample(range(2, frame_count + 1), 4)
    for frame in frames:
        assert_analyze(frame)


def test_benchmark():
    expected = []
    for frame in range(1, 6):
        raw = get_expected_frame_bytes(frame)
        expected.append((len(raw), hashlib.sha256(raw).hexdigest()))

    open(FFMPEG_LOG, "w").close()
    try:
        response = requests.get(f"{BASE_URL}/benchmark", timeout=15)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /benchmark: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type: application/json"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "frames_processed" in data, "Missing 'frames_processed' in response"
    assert "time_ms" in data, "Missing 'time_ms' in response"
    assert data["frames_processed"] == 5, f"Expected frames_processed to be 5, got {data['frames_processed']}"
    assert isinstance(data["time_ms"], (int, float)), "time_ms must be a number"
    assert data["time_ms"] > 0, f"Expected time_ms to be > 0, got {data['time_ms']}"

    with open(FFMPEG_LOG, encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert len(calls) >= 5, "The benchmark did not invoke the pre-installed ffmpeg for all five analyses"

    observed = collections.Counter()
    for call in calls:
        assert call["returncode"] == 0, "An ffmpeg invocation made by /benchmark failed"
        for artifact in call.get("hashes", []):
            observed[(artifact["length"], artifact["sha256"])] += 1

    required = collections.Counter(expected)
    missing = required - observed
    assert not missing, "The benchmark did not extract the raw grayscale data for each of frames 1 through 5"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
