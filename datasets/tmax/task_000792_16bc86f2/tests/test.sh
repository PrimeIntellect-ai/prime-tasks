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
import gzip
import re
import secrets
import subprocess
import tarfile
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
VIDEO_PATH = "/app/security_cam.mp4"
ARCHIVE_PATH = "/app/backup_root.tar.gz"
FIXED_TIMESTAMPS = [2.5, 7.1, 15.3]

# Choose previously unknown, non-boundary query times after the agent has started.
_rng = secrets.SystemRandom()
_random_milliseconds = _rng.sample(
    [ms for ms in range(101, 29500) if ms % 1000 != 0], 12
)
RANDOM_TIMESTAMPS = [ms / 1000.0 for ms in _random_milliseconds]


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.5)
    return False


def recover_expected_timestamps():
    chunks = []
    pattern = re.compile(r"(?:^|/)chunk_(\d+)\.bin\.gz$")
    with tarfile.open(ARCHIVE_PATH, "r:gz") as archive:
        for member in archive.getmembers():
            match = pattern.search(member.name)
            if not match or not member.isfile():
                continue
            extracted = archive.extractfile(member)
            assert extracted is not None
            values = gzip.decompress(extracted.read()).decode("utf-8").splitlines()
            chunks.append((int(match.group(1)), [v.strip() for v in values if v.strip()]))

    assert chunks, "No timestamp chunks found in the archive"
    values = []
    for _, chunk_values in sorted(chunks, key=lambda item: item[0]):
        values.extend(chunk_values)
    return ",".join(sorted(values, key=float))


@pytest.fixture(scope="module", autouse=True)
def setup_server():
    assert wait_for_server(f"{BASE_URL}/ping"), f"Server at {BASE_URL} is not responding."


def test_ping_endpoint():
    response = requests.get(f"{BASE_URL}/ping", timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.text.strip() == "pong", f"Expected 'pong', got '{response.text}'"


def test_timestamps_endpoint():
    response = requests.get(f"{BASE_URL}/api/timestamps", timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"

    # Retain the original assertion and independently derive the answer from the archive.
    expected_timestamps = "2.5,7.1,12.0,15.3,22.8"
    assert response.text.strip() == expected_timestamps, \
        f"Expected '{expected_timestamps}', got '{response.text}'"
    archive_expected = recover_expected_timestamps()
    assert archive_expected == expected_timestamps, "Archive contents differ from the task fixture"
    assert response.text.strip() == archive_expected


def get_expected_brightness(timestamp: float, video_path: str) -> int:
    cmd = [
        "ffmpeg", "-ss", str(timestamp), "-i", video_path,
        "-vframes", "1", "-f", "image2pipe", "-vcodec", "rawvideo",
        "-pix_fmt", "gray", "-"
    ]
    result = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15
    )
    data = result.stdout
    if not data:
        return 0
    return sum(data) // len(data)


@pytest.mark.parametrize("timestamp", FIXED_TIMESTAMPS)
def test_frame_brightness_endpoint_fixed(timestamp):
    response = requests.get(
        f"{BASE_URL}/api/frame_brightness", params={"time": timestamp}, timeout=15
    )
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    expected_brightness = get_expected_brightness(timestamp, VIDEO_PATH)
    actual_brightness = response.text.strip()
    assert actual_brightness == str(expected_brightness), \
        f"For time {timestamp}, expected brightness {expected_brightness}, got {actual_brightness}"


@pytest.mark.parametrize("timestamp", RANDOM_TIMESTAMPS)
def test_frame_brightness_endpoint_random(timestamp):
    response = requests.get(
        f"{BASE_URL}/api/frame_brightness", params={"time": timestamp}, timeout=15
    )
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    expected_brightness = get_expected_brightness(timestamp, VIDEO_PATH)
    actual_brightness = response.text.strip()
    assert actual_brightness == str(expected_brightness), \
        f"For time {timestamp}, expected brightness {expected_brightness}, got {actual_brightness}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
