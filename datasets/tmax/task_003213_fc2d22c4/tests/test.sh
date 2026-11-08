#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_original_state.py
import requests
import pytest

URL = "http://127.0.0.1:8080/api/v1/flash-telemetry"
VALID_TOKEN = "SecretAdminToken99"

def test_unauthorized_missing_token():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"

def test_unauthorized_invalid_token():
    headers = {"Authorization": "Bearer InvalidToken123"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {response.status_code}"

def test_authorized_valid_response():
    headers = {"Authorization": f"Bearer {VALID_TOKEN}"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK for valid token, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "flash_events" in data, "Response JSON missing 'flash_events' key"
    events = data["flash_events"]
    assert isinstance(events, list), "'flash_events' should be a list"
    assert len(events) == 3, f"Expected 3 flash events, got {len(events)}"

    frame_indices = [event.get("frame_index") for event in events]
    assert frame_indices == sorted(frame_indices), "Events are not sorted by frame_index in ascending order"

    expected_frames = [25, 42, 88]
    expected_alerts = ["alert_1", "alert_2", "alert_3"]
    for i, event in enumerate(events):
        assert event.get("frame_index") == expected_frames[i], f"Expected frame_index {expected_frames[i]}, got {event.get('frame_index')}"
        assert event.get("sensor_reading") == expected_alerts[i], f"Expected sensor_reading {expected_alerts[i]}, got {event.get('sensor_reading')}"
        brightness = event.get("brightness")
        assert isinstance(brightness, (int, float)), f"Brightness should be a number, got {type(brightness)}"
        assert brightness > 200.0, f"Expected brightness > 200.0, got {brightness}"
        assert 250.0 <= brightness <= 255.0, f"Expected brightness close to 255.0, got {brightness}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_pipeline.py
import json
import os
import random
import secrets
import signal
import subprocess
import tempfile
import time

import requests

URL = "http://127.0.0.1:8080/api/v1/flash-telemetry"
TOKEN = "SecretAdminToken99"
PORT_HEX = format(8080, "04X")


def listening_inodes():
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[-1].upper() == PORT_HEX:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids():
    inodes = listening_inodes()
    found = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return found


def process_description(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert argv, "Listening server has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as f:
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return argv, cwd, env


def stop_listeners():
    deadline = time.time() + 5
    while time.time() < deadline:
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.2)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    assert not listener_pids(), "Could not stop the submitted server"


def make_inputs():
    rng = random.SystemRandom()
    frame_count = 48
    flash_indices = sorted(rng.sample(range(3, frame_count - 3), 6))
    flash_set = set(flash_indices)
    source_levels = []
    readings = {}

    frame_dir = tempfile.mkdtemp(prefix="dynamic_frames_")
    for i in range(frame_count):
        level = rng.randint(215, 245) if i in flash_set else rng.randint(10, 165)
        source_levels.append(level)
        with open(os.path.join(frame_dir, f"frame_{i:03d}.pgm"), "w") as f:
            f.write("P2\n16 16\n255\n")
            f.write((str(level) + " ") * 256 + "\n")

    subprocess.run([
        "ffmpeg", "-loglevel", "error", "-y", "-framerate", "30",
        "-i", os.path.join(frame_dir, "frame_%03d.pgm"),
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "/app/dashboard_recording.mp4"
    ], check=True)

    suffixes = ["\\u00", "", "\\uZZZZ"]
    with open("/app/telemetry_stream.jsonl", "w") as f:
        for i in range(frame_count):
            reading = f"reading_{i}_{secrets.token_hex(6)}"
            readings[i] = reading
            record = json.dumps({"frame_index": i, "sensor_reading": reading})
            f.write(record + suffixes[i % len(suffixes)] + "\n")
        f.write("this line is not recoverable JSON \\u0\n")

    raw = subprocess.check_output([
        "ffmpeg", "-loglevel", "error", "-i", "/app/dashboard_recording.mp4",
        "-f", "rawvideo", "-pix_fmt", "gray", "-"
    ])
    pixels_per_frame = 16 * 16
    assert len(raw) % pixels_per_frame == 0
    brightness = [
        sum(raw[pos:pos + pixels_per_frame]) / pixels_per_frame
        for pos in range(0, len(raw), pixels_per_frame)
    ]
    assert len(brightness) == frame_count

    expected = [
        {"frame_index": i, "brightness": brightness[i], "sensor_reading": readings[i]}
        for i in range(frame_count) if brightness[i] > 200.0
    ]
    assert [e["frame_index"] for e in expected] == flash_indices
    return expected


pids = listener_pids()
assert len(pids) == 1, f"Expected exactly one server listening on port 8080, found {sorted(pids)}"
argv, cwd, env = process_description(next(iter(pids)))
expected = make_inputs()
stop_listeners()

proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    deadline = time.time() + 15
    response = None
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Submitted server exited during restart with code {proc.returncode}")
        try:
            response = requests.get(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=1)
            if response.status_code == 200:
                break
        except requests.RequestException:
            pass
        time.sleep(0.25)
    assert response is not None and response.status_code == 200, "Restarted server did not become ready"

    missing = requests.get(URL, timeout=5)
    assert missing.status_code == 401, f"Expected 401 without token, got {missing.status_code}"
    invalid = requests.get(URL, headers={"Authorization": "Bearer InvalidToken123"}, timeout=5)
    assert invalid.status_code == 401, f"Expected 401 for invalid token, got {invalid.status_code}"

    response = requests.get(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=5)
    assert response.status_code == 200, f"Expected 200 with valid token, got {response.status_code}"
    try:
        data = response.json()
    except ValueError as exc:
        raise AssertionError("Dynamic response is not valid JSON") from exc

    assert "flash_events" in data, "Response JSON missing 'flash_events' key"
    events = data["flash_events"]
    assert isinstance(events, list), "'flash_events' should be a list"
    assert len(events) == len(expected), f"Expected {len(expected)} dynamic flash events, got {len(events)}"
    indices = [event.get("frame_index") for event in events]
    assert indices == sorted(indices), "Dynamic events are not sorted by frame_index"

    for event, truth in zip(events, expected):
        assert event.get("frame_index") == truth["frame_index"], (event, truth)
        assert event.get("sensor_reading") == truth["sensor_reading"], (event, truth)
        value = event.get("brightness")
        assert isinstance(value, (int, float)) and not isinstance(value, bool), "Brightness must be numeric"
        assert value > 200.0, f"Flash brightness must exceed 200.0, got {value}"
        assert abs(float(value) - truth["brightness"]) <= 2.5, (
            f"Brightness for frame {truth['frame_index']} was {value}; "
            f"independently decoded value is {truth['brightness']}"
        )
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
DYNAMIC_EOF

ok=1
python3 -m pytest /tmp/test_original_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_dynamic_pipeline.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
