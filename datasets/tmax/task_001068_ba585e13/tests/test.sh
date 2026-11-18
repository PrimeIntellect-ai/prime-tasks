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
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest
import requests

VIDEO = "/app/test_sequence.mp4"


def get_expected_score(frame_num):
    cmd = [
        "ffmpeg", "-i", VIDEO,
        "-vf", f"select=eq(n\\,{frame_num})",
        "-vframes", "1",
        "-pix_fmt", "gray",
        "-f", "image2pipe",
        "-vcodec", "rawvideo",
        "-"
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode != 0 or not result.stdout:
        pytest.fail(f"Failed to extract frame {frame_num} using ffmpeg")

    data = result.stdout
    sum_val = sum(data)
    max_val = max(data) if data else 0

    if max_val == 255:
        return -1
    return sum_val // (255 - max_val)


def assert_score(frame):
    expected = get_expected_score(frame)
    url = f"http://127.0.0.1:9000/score?frame={frame}"
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to service for frame {frame} at {url}: {e}")

    assert resp.status_code == 200, f"Expected HTTP 200 OK for frame {frame}, got {resp.status_code}"
    assert resp.text.strip() == str(expected), \
        f"Expected score {expected} for frame {frame}, got '{resp.text.strip()}'"


@pytest.mark.parametrize("frame", [0, 10, 42])
def test_score_endpoint(frame):
    assert_score(frame)


def test_randomized_video_and_arbitrary_frames():
    width, height, frame_count = 320, 240, 12
    boundary_frame = secrets.randbelow(frame_count)
    backup = f"/app/.verifier_backup_{secrets.token_hex(8)}.mp4"
    challenge = f"/app/.verifier_challenge_{secrets.token_hex(8)}.mp4"
    raw_fd, raw_path = tempfile.mkstemp(suffix=".gray")
    os.close(raw_fd)

    shutil.copy2(VIDEO, backup)
    try:
        with open(raw_path, "wb") as raw:
            for frame in range(frame_count):
                cap = 40 + secrets.randbelow(191)
                pixels = bytearray(os.urandom(width * height))
                for i, value in enumerate(pixels):
                    if value > cap:
                        pixels[i] = cap
                pixels[0] = 255 if frame == boundary_frame else cap
                raw.write(pixels)

        encode = subprocess.run([
            "ffmpeg", "-y",
            "-f", "rawvideo",
            "-pixel_format", "gray",
            "-video_size", f"{width}x{height}",
            "-framerate", "24",
            "-i", raw_path,
            "-c:v", "libx264", "-crf", "0", "-preset", "ultrafast",
            challenge
        ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        assert encode.returncode == 0, \
            f"Failed to create verifier challenge video: {encode.stderr.decode(errors='replace')}"

        os.replace(challenge, VIDEO)
        frames = list(range(frame_count))
        random.SystemRandom().shuffle(frames)
        for frame in frames:
            assert_score(frame)
    finally:
        if os.path.exists(backup):
            os.replace(backup, VIDEO)
        if os.path.exists(challenge):
            os.unlink(challenge)
        if os.path.exists(raw_path):
            os.unlink(raw_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
