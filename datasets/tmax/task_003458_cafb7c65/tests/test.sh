#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import os
import pwd
import secrets
import stat
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
import requests


@pytest.fixture(scope="module", autouse=True)
def wait_for_server():
    """Wait for the server to be ready before running any tests."""
    ready_file = "/home/user/app/server_ready.log"
    wait_time = 0
    ready = False
    while wait_time < 30:
        if os.path.exists(ready_file):
            with open(ready_file, "r") as f:
                if "READY" in f.read():
                    ready = True
                    break
        time.sleep(1)
        wait_time += 1
    assert ready, "Server never became ready (did not write 'READY' to /home/user/app/server_ready.log within 30 seconds)."


def decode_response(resp, expected_frame):
    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert "frame" in data, "Response JSON missing 'frame' key"
    assert "data" in data, "Response JSON missing 'data' key"
    assert data["frame"] == expected_frame, f"Expected frame {expected_frame}, got {data['frame']}"
    assert isinstance(data["data"], str), "Response 'data' must be a string"
    try:
        return base64.b64decode(data["data"][::-1], validate=True)
    except Exception as e:
        pytest.fail(f"Failed to decode base64 data: {e}. Ensure the data is a valid reversed Base64 string.")


def test_correctness():
    """Verify that the API returns the correct JSON format and properly encoded JPEG data."""
    try:
        resp = requests.get("http://127.0.0.1:8000/api/v1/frame/15", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "frame" in data, "Response JSON missing 'frame' key"
    assert "data" in data, "Response JSON missing 'data' key"
    assert data["frame"] == 15, f"Expected frame 15, got {data['frame']}"

    reversed_b64 = data["data"]
    actual_b64 = reversed_b64[::-1]

    try:
        jpeg_bytes = base64.b64decode(actual_b64, validate=True)
    except Exception as e:
        pytest.fail(f"Failed to decode base64 data: {e}. Ensure the data is a valid reversed Base64 string.")

    assert jpeg_bytes.startswith(b'\xff\xd8'), "Decoded data is not a valid JPEG (missing JPEG magic bytes '\\xff\\xd8')"


def test_frames_match_video():
    """Compare unpredictable requested frames with frames decoded from the source video."""
    width, height = 96, 54
    frame_size = width * height * 3
    source = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", "/app/project_video.mp4",
            "-vf", f"scale={width}:{height}:flags=area",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=True,
    ).stdout
    assert len(source) >= frame_size and len(source) % frame_size == 0, "Could not decode source video frames"
    source_frames = [source[i:i + frame_size] for i in range(0, len(source), frame_size)]
    frame_count = len(source_frames)
    assert frame_count > 15, "Source video does not contain the frame used by the API check"

    fixed = {0, 15, frame_count - 1}
    remaining = [i for i in range(frame_count) if i not in fixed]
    chosen = sorted(fixed | set(secrets.SystemRandom().sample(remaining, min(9, len(remaining)))))
    returned_payloads = []

    for number in chosen:
        try:
            response = requests.get(f"http://127.0.0.1:8000/api/v1/frame/{number}", timeout=5)
        except requests.RequestException as e:
            pytest.fail(f"Failed to request frame {number}: {e}")
        jpeg = decode_response(response, number)
        assert jpeg.startswith(b'\xff\xd8'), f"Frame {number} is not JPEG data"
        returned_payloads.append(jpeg)

        decoded = subprocess.run(
            [
                "ffmpeg", "-v", "error", "-f", "image2pipe", "-vcodec", "mjpeg",
                "-i", "pipe:0", "-frames:v", "1",
                "-vf", f"scale={width}:{height}:flags=area",
                "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
            ],
            input=jpeg,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert decoded.returncode == 0, f"JPEG returned for frame {number} could not be decoded"
        assert len(decoded.stdout) == frame_size, f"JPEG returned for frame {number} has the wrong dimensions or content"

        distances = [
            sum(abs(a - b) for a, b in zip(decoded.stdout, candidate)) / frame_size
            for candidate in source_frames
        ]
        requested_distance = distances[number]
        closest = min(range(frame_count), key=distances.__getitem__)
        assert requested_distance < 18.0, (
            f"Image returned for frame {number} does not visually match that frame "
            f"(mean pixel error {requested_distance:.2f})"
        )
        assert closest == number, (
            f"Image requested as frame {number} most closely matches source frame {closest}"
        )

    assert len(set(returned_payloads)) > 1, "The server returned the same JPEG payload for every requested frame"


def test_performance_rps():
    """Benchmark the API to ensure it meets the minimum Requests Per Second (RPS) threshold."""
    num_requests = 300
    start_time = time.time()

    def fetch(i):
        try:
            # Request random frames between 0 and 89 (3 seconds at 30fps)
            r = requests.get(f"http://127.0.0.1:8000/api/v1/frame/{i % 90}", timeout=5)
            return r.status_code
        except Exception:
            return 500

    with ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(fetch, range(num_requests)))

    end_time = time.time()

    successes = [r for r in results if r == 200]
    success_rate = len(successes) / num_requests
    assert success_rate >= 0.95, f"Too many failed requests during load test. Success rate: {success_rate*100:.1f}% (Expected >= 95%)"

    duration = end_time - start_time
    rps = num_requests / duration

    assert rps >= 150, f"Performance metric failed: achieved {rps:.2f} RPS, threshold is >= 150 RPS. Ensure frames are pre-extracted or cached."


def test_required_pytest_suite():
    """Ensure the requested pytest/mock suite exists and succeeds without access to the real video."""
    test_path = "/home/user/app/test_server.py"
    try:
        mode = os.lstat(test_path).st_mode
    except FileNotFoundError:
        pytest.fail("Required /home/user/app/test_server.py does not exist")
    assert stat.S_ISREG(mode), "/home/user/app/test_server.py must be a regular file"

    with open(test_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=test_path)
    test_defs = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test_")]
    assert test_defs, "test_server.py does not define any pytest tests"

    imports_mock = False
    uses_mock = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports_mock |= any(alias.name == "unittest.mock" for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imports_mock |= node.module == "unittest.mock" or (
                node.module == "unittest" and any(alias.name == "mock" for alias in node.names)
            )
        elif isinstance(node, ast.Call):
            func = node.func
            name = func.id if isinstance(func, ast.Name) else func.attr if isinstance(func, ast.Attribute) else ""
            if name in {"patch", "patch.object", "Mock", "MagicMock", "create_autospec"} or name == "object":
                uses_mock = True
    assert imports_mock, "test_server.py must import unittest.mock"
    assert uses_mock, "test_server.py must use unittest.mock to replace video extraction logic"

    video = "/app/project_video.mp4"
    hidden = f"/tmp/project_video.hidden.{os.getpid()}.{secrets.token_hex(8)}"
    original_mode = stat.S_IMODE(os.stat(video).st_mode)
    os.replace(video, hidden)
    os.chmod(hidden, 0)
    account = pwd.getpwnam("user")

    def drop_privileges():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        result = subprocess.run(
            ["python3", "-m", "pytest", "-q", "test_server.py"],
            cwd="/home/user/app",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
            preexec_fn=drop_privileges,
        )
    finally:
        os.chmod(hidden, original_mode)
        os.replace(hidden, video)

    assert result.returncode == 0, "Required test_server.py suite failed:\n" + result.stdout[-6000:]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
