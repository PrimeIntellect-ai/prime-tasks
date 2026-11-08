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
import functools
import json
import os
import re
import signal
import subprocess

import pytest
import requests

SCRIPT = "/app/bisect_anomaly.sh"
VIDEO = "/app/incident_capture.mp4"


def anomalous_frame(video):
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json", video,
        ],
        check=True, capture_output=True, text=True, timeout=15,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    frame_size = width * height

    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", video, "-map", "0:v:0",
            "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1",
        ],
        check=True, capture_output=True, timeout=30,
    ).stdout
    assert frame_size and len(decoded) % frame_size == 0, "Could not decode complete video frames"

    black = []
    for index in range(len(decoded) // frame_size):
        frame = decoded[index * frame_size:(index + 1) * frame_size]
        if sum(frame) / frame_size < 50:
            black.append(index)
    assert len(black) == 1, f"Expected exactly one black frame in {video}, found {black}"
    return black[0]


@functools.lru_cache(maxsize=1)
def incident_anomaly():
    return anomalous_frame(VIDEO)


def run_script(video, timeout=60):
    assert os.path.isfile(SCRIPT), f"Missing required script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script is not executable: {SCRIPT}"
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, "bisect_anomaly.sh must remain a Bash script"

    proc = subprocess.Popen(
        [SCRIPT, video], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(f"bisect_anomaly.sh failed to converge for {video}")

    assert proc.returncode == 0, (
        f"bisect_anomaly.sh exited with {proc.returncode}\nstdout: {stdout}\nstderr: {stderr}"
    )
    matches = re.findall(r"Found\s+anomaly\s+at\s+frame:\s*(\d+)", stdout, re.IGNORECASE)
    assert matches, f"Script did not report the anomalous frame. stdout: {stdout!r}"
    return int(matches[-1])


def test_fixed_script_on_incident_capture():
    assert run_script(VIDEO) == incident_anomaly()


def test_fixed_script_on_independent_capture(tmp_path):
    alternate = tmp_path / "alternate_capture.mp4"
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
            "color=c=white:s=64x48:r=25:d=0.8",
            "-vf", "geq=lum='if(eq(N,7),0,255)':cb=128:cr=128",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", str(alternate),
        ],
        check=True, timeout=30,
    )
    expected = anomalous_frame(str(alternate))
    assert expected != incident_anomaly(), "Independent fixture did not move the anomaly"
    assert run_script(str(alternate)) == expected


def test_anomaly_endpoint():
    url = "http://127.0.0.1:8888/anomaly"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to {url} or request timed out: {e}"

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        assert False, f"Response body is not valid JSON: {response.text}"

    assert "frame" in data, f"JSON response is missing the 'frame' key. Got: {data}"
    expected = incident_anomaly()
    assert data["frame"] == expected, f"Expected frame number to be {expected}, but got {data['frame']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
