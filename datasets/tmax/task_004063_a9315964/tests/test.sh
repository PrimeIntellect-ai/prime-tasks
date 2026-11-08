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
import hashlib
import json
import subprocess

import pytest
import requests

VIDEO_PATH = "/app/evidence.mp4"
BASE_URL = "http://127.0.0.1:8080"


def derive_secret_key():
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json", VIDEO_PATH,
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width = int(stream["width"])
    height = int(stream["height"])
    frame_size = width * height * 3

    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-map", "0:v:0", "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout

    assert len(decoded) % frame_size == 0, "Decoded video ended with an incomplete frame"
    pure_red_pixel = b"\xff\x00\x00"
    pure_red_frame = pure_red_pixel * (width * height)
    red_count = sum(
        decoded[offset:offset + frame_size] == pure_red_frame
        for offset in range(0, len(decoded), frame_size)
    )
    return hashlib.sha256(f"RED_FRAMES_{red_count}".encode("ascii")).hexdigest()


SECRET_KEY = derive_secret_key()


def test_health_endpoint():
    """Verify the /health endpoint returns 200 OK with body 'OK'."""
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/health. Is the Go server running? Error: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /health, got {response.status_code}"
    assert response.text == "OK", f"Expected body 'OK' for /health, got '{response.text}'"


def test_command_endpoint_unauthorized():
    """Verify /command rejects a missing secret key."""
    try:
        response = requests.post(f"{BASE_URL}/command", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/command. Error: {e}")

    assert response.status_code == 401, f"Expected status code 401 for /command without X-Secret-Key header, got {response.status_code}"


def test_command_endpoint_incorrect_key():
    """Verify /command rejects an incorrect nonempty secret key."""
    wrong_key = ("0" if SECRET_KEY[0] != "0" else "1") + SECRET_KEY[1:]
    try:
        response = requests.post(
            f"{BASE_URL}/command",
            headers={"X-Secret-Key": wrong_key},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/command. Error: {e}")

    assert response.status_code == 401, f"Expected status code 401 for /command with an incorrect X-Secret-Key header, got {response.status_code}"


def test_command_endpoint_authorized():
    """Verify /command accepts the key derived from exact decoded RGB frames."""
    headers = {"X-Secret-Key": SECRET_KEY}
    try:
        response = requests.post(f"{BASE_URL}/command", headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/command. Error: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /command with correct X-Secret-Key header, got {response.status_code}"
    assert response.text == "COMMAND_ACCEPTED", f"Expected body 'COMMAND_ACCEPTED' for /command, got '{response.text}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
