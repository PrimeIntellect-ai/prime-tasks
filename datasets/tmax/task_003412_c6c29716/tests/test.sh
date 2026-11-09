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
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080/api/v1/video-auth"


def get(url, timeout=15):
    try:
        return requests.get(url, timeout=timeout)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server: {e}")


def test_ts_0():
    response = get(f"{BASE_URL}?ts=0", timeout=10)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "MjU=", f"Expected MjU=, got {response.text.strip()}"


def test_ts_1():
    response = get(f"{BASE_URL}?ts=1", timeout=10)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "MzI=", f"Expected MzI=, got {response.text.strip()}"


def test_ts_injection():
    response = get(f"{BASE_URL}?ts=1;ls", timeout=10)
    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "Invalid Input", f"Expected 'Invalid Input', got {response.text.strip()}"


def test_ts_3_malicious_qr():
    response = get(f"{BASE_URL}?ts=3", timeout=10)
    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "Invalid Input", f"Expected 'Invalid Input', got {response.text.strip()}"


def test_ts_4():
    response = get(f"{BASE_URL}?ts=4", timeout=10)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "OTA=", f"Expected OTA=, got {response.text.strip()}"


def test_randomized_video_and_adversarial_inputs():
    assert os.path.isfile("/home/user/server.sh"), "Missing /home/user/server.sh"

    rng = secrets.SystemRandom()
    token = secrets.token_hex(12)
    qr_marker = f"/tmp/qr_payload_executed_{token}"
    ts_marker = f"/tmp/ts_payload_executed_{token}"
    for marker in (qr_marker, ts_marker):
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass

    add_a, add_b = rng.randint(200, 999), rng.randint(20, 99)
    sub_a, sub_b = rng.randint(300, 999), rng.randint(10, 199)
    mul_a, mul_b = rng.randint(20, 99), rng.randint(11, 49)
    quotient, divisor = rng.randint(101, 999), rng.randint(2, 25)

    frames = [
        (f"{add_a} + {add_b}", add_a + add_b),
        (f"{sub_a} - {sub_b}", sub_a - sub_b),
        (f"{mul_a} * {mul_b}", mul_a * mul_b),
        (f"{quotient * divisor} / {divisor}", quotient),
        (f"$(touch${{IFS}}{qr_marker})", None),
        (f"system(\"random-{token}\")", None),
    ]
    rng.shuffle(frames)

    with tempfile.TemporaryDirectory(prefix="video-auth-test-") as frame_dir:
        for index, (payload, _) in enumerate(frames):
            subprocess.run(
                ["qrencode", "-s", "10", "-o", os.path.join(frame_dir, f"frame{index}.png"), payload],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=15,
            )

        staged_video = f"/app/.auth_events_{token}.mp4"
        try:
            subprocess.run(
                [
                    "ffmpeg", "-y", "-loglevel", "error", "-framerate", "1",
                    "-i", os.path.join(frame_dir, "frame%d.png"),
                    "-vf", "scale=320:320:flags=neighbor", "-c:v", "libx264",
                    "-r", "30", "-pix_fmt", "yuv420p", staged_video,
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=60,
            )
            os.chmod(staged_video, 0o644)
            os.replace(staged_video, "/app/auth_events.mp4")
        finally:
            if os.path.exists(staged_video):
                os.unlink(staged_video)

    for index, (_, expected) in enumerate(frames):
        fraction = rng.randint(15, 75)
        response = get(f"{BASE_URL}?ts={index}.{fraction:02d}")
        if expected is None:
            assert response.status_code == 400, (
                f"Expected 400 for randomized malicious QR at frame {index}, "
                f"got {response.status_code}. Response: {response.text}"
            )
            assert response.text.strip() == "Invalid Input"
        else:
            encoded = base64.b64encode(str(expected).encode()).decode()
            assert response.status_code == 200, (
                f"Expected 200 for randomized frame {index}, got {response.status_code}. "
                f"Response: {response.text}"
            )
            assert response.text.strip() == encoded, (
                f"Randomized frame {index}: expected {encoded}, got {response.text.strip()}"
            )

    assert not os.path.exists(qr_marker), "The malicious QR payload was executed"

    injection = f"1;touch${{IFS}}{ts_marker}"
    response = get(f"{BASE_URL}?ts={injection}")
    assert response.status_code == 400, f"Expected 400 for timestamp injection, got {response.status_code}"
    assert response.text.strip() == "Invalid Input"
    assert not os.path.exists(ts_marker), "The malicious timestamp payload was executed"

    malformed = f"not-a-timestamp-{secrets.token_hex(8)}"
    response = get(f"{BASE_URL}?ts={malformed}")
    assert response.status_code == 400, f"Expected 400 for malformed timestamp, got {response.status_code}"
    assert response.text.strip() == "Invalid Input"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
