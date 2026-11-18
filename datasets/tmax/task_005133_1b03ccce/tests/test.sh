#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import time
import subprocess

import cv2
import requests

BASE_URL = "http://localhost:8000"


def video_luminance(frame_number, x, y):
    cap = cv2.VideoCapture("/app/video.mp4")
    assert cap.isOpened(), "Verifier could not open /app/video.mp4"
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_number)
    ok, frame = cap.read()
    cap.release()
    assert ok, f"Verifier could not read frame {frame_number}"
    b, g, r = [int(v) for v in frame[y, x]]
    return int(0.299 * r + 0.587 * g + 0.114 * b)


def post(script, client_id):
    return requests.post(
        BASE_URL + "/execute",
        json={"script": script, "client_id": client_id},
        timeout=5,
    )


def assert_result(script, client_id, expected, tolerance=1):
    response = post(script, client_id)
    assert response.status_code == 200, response.text
    value = response.json().get("result")
    assert type(value) is int, f"result is not an integer: {value!r}"
    assert abs(value - expected) <= tolerance, (
        f"wrong result for {script!r}: got {value}, expected {expected}"
    )


def test_api_accuracy_and_behavior():
    app_path = "/home/user/app.py"
    assert os.path.exists(app_path), f"FastAPI app {app_path} does not exist."

    process = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app:app", "--port", "8000"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    try:
        time.sleep(3)
        assert process.poll() is None, "uvicorn exited before tests began"

        # Preserve all five checks made by the original verifier.
        score = 0
        total = 5
        script1 = "SEEK 10\nLUM 50 50 R1\nRET R1"
        try:
            r1 = post(script1, "client1")
            if r1.status_code == 200 and isinstance(r1.json().get("result"), int):
                score += 1
        except Exception:
            pass

        try:
            post(script1, "client1")
            post(script1, "client1")
            r2 = post(script1, "client1")
            if r2.status_code == 429:
                score += 1
        except Exception:
            pass

        try:
            r3 = post("INVALID COMMAND", "client2")
            if r3.status_code == 400:
                score += 1
        except Exception:
            pass

        script2 = "SEEK 0\nLUM 10 10 R0\nADD R1 R0\nRET R1"
        try:
            r4 = post(script2, "client3")
            if r4.status_code == 200 and isinstance(r4.json().get("result"), int):
                score += 1
        except Exception:
            pass

        try:
            time.sleep(21)
            r5 = post(script1, "client1")
            if r5.status_code == 200:
                score += 1
        except Exception:
            pass

        accuracy = score / total
        assert accuracy >= 1.0, f"API Accuracy Score: {accuracy} < 1.0 (Target: 1.0)"

        # Derive pixel answers from the actual shipped video and verify SEEK/LUM.
        white0 = video_luminance(0, 20, 220)
        black20 = video_luminance(20, 20, 220)
        white20 = video_luminance(20, 120, 220)
        assert white0 > 100 and white20 > 100 and black20 < 100

        assert_result("SEEK 0\nLUM 20 220 R2\nRET R2", "pixel-frame-0", white0)
        assert_result("SEEK 20\nLUM 20 220 R2\nRET R2", "pixel-frame-20", black20)

        # Verify register addition numerically.
        assert_result(
            "SEEK 20\nLUM 120 220 R0\nADD R0 R0\nRET R0",
            "addition",
            2 * white20,
            tolerance=2,
        )

        # Verify both taken and non-taken JGT branches using video-derived values.
        assert_result(
            "SEEK 0\nLUM 20 220 R0\nJGT R0 100 4\nRET R1\nRET R0",
            "jgt-taken",
            white0,
        )
        assert_result(
            "SEEK 20\nLUM 20 220 R0\nJGT R0 100 5\nLUM 120 220 R1\nRET R1\nRET R0",
            "jgt-not-taken",
            white20,
        )

        # Invalid opcodes, arities, operands, registers, and jump targets are scripts
        # containing invalid commands and must receive HTTP 400.
        invalid_scripts = [
            "SEEK",
            "LUM 1 2 R9\nRET R0",
            "ADD R0\nRET R0",
            "JGT R0 nope 0\nRET R0",
            "JGT R0 0 99\nRET R0",
            "RET RX",
            "RET R0\nGARBAGE",
        ]
        for index, script in enumerate(invalid_scripts):
            response = post(script, f"invalid-{index}")
            assert response.status_code == 400, (
                f"invalid script returned {response.status_code}: {script!r}"
            )
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

    # The requested pytest suite must exist, collect tests, and pass.
    suite = "/home/user/tests/test_api.py"
    assert os.path.isfile(suite), f"Required pytest suite {suite} does not exist"
    completed = subprocess.run(
        [sys.executable, "-m", "pytest", suite, "-q", "--tb=short"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert completed.returncode == 0, "Submitted pytest suite failed:\n" + completed.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
