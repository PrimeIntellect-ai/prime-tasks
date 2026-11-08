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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import random
import subprocess
import time
from pathlib import Path

import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer MATH-TOKEN-2024"}
REQUEST_TIMES = []


def paced_post(**kwargs):
    """Keep non-rate-limit tests below four requests per rolling second."""
    global REQUEST_TIMES
    now = time.monotonic()
    REQUEST_TIMES = [t for t in REQUEST_TIMES if now - t < 1.1]
    if len(REQUEST_TIMES) >= 4:
        time.sleep(max(0, 1.1 - (now - REQUEST_TIMES[0])))
        now = time.monotonic()
        REQUEST_TIMES = [t for t in REQUEST_TIMES if now - t < 1.1]
    response = requests.post(f"{BASE_URL}/evaluate", timeout=5, **kwargs)
    REQUEST_TIMES.append(time.monotonic())
    return response


def decoded_rgb_frames():
    frame_size = 100 * 100 * 3
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", "/app/color_math.mp4",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-vsync", "0", "-"
    ])
    assert len(raw) == 100 * frame_size, (
        f"Expected exactly 100 decoded frames, got {len(raw) / frame_size}"
    )
    return [tuple(raw[i * frame_size:i * frame_size + 3]) for i in range(100)]


FRAMES = decoded_rgb_frames()


def assert_result(expression, frame, expected):
    response = paced_post(
        headers=AUTH_HEADER,
        json={"expression": expression, "frame": frame},
    )
    assert response.status_code == 200, (
        f"Expected 200 for {expression!r} at frame {frame}, got "
        f"{response.status_code}: {response.text}"
    )
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert isinstance(data["result"], (int, float)) and not isinstance(data["result"], bool)
    assert math.isclose(float(data["result"]), float(expected), rel_tol=1e-9, abs_tol=1e-9), (
        f"For {expression!r} at frame {frame}, expected {expected}, got {data['result']}"
    )


def test_modular_python_project_and_safe_parser():
    app_dir = Path("/home/user/project/app")
    assert app_dir.is_dir(), "Missing required /home/user/project/app directory"
    modules = [p for p in app_dir.rglob("*.py") if p.name != "__init__.py"]
    assert len(modules) >= 3, "Expected the server, parser, and video logic to be split into modules"

    combined_source = "\n".join(p.read_text(errors="replace") for p in modules)
    assert "color_math.mp4" in combined_source, "Python project does not reference the video artifact"
    assert any(marker in combined_source.lower() for marker in (
        "ffmpeg", "videocapture", "cv2", "imageio", "av.open", "subprocess"
    )), "No video decoding/extraction implementation was found"

    for module in modules:
        tree = ast.parse(module.read_text(errors="replace"), filename=str(module))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                assert node.func.id not in {"eval", "exec"}, (
                    f"Forbidden {node.func.id}() call in {module}"
                )


def test_missing_auth():
    response = paced_post(json={"expression": "R + G", "frame": 10})
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"


def test_invalid_auth():
    response = paced_post(
        headers={"Authorization": "Bearer INVALID-TOKEN"},
        json={"expression": "R + G", "frame": 10},
    )
    assert response.status_code == 401, f"Expected 401 for invalid auth, got {response.status_code}"


def test_invalid_frame():
    response = paced_post(
        headers=AUTH_HEADER,
        json={"expression": "R + G", "frame": 150},
    )
    assert response.status_code == 400, f"Expected 400 for invalid frame, got {response.status_code}"

    for invalid in (-1, 100, 1.5, "10", True):
        response = paced_post(
            headers=AUTH_HEADER,
            json={"expression": "R + G", "frame": invalid},
        )
        assert response.status_code == 400, f"Expected 400 for invalid frame {invalid!r}, got {response.status_code}"


def test_invalid_variables():
    for expression in ("R + X", "red + G", "R + g"):
        response = paced_post(
            headers=AUTH_HEADER,
            json={"expression": expression, "frame": 10},
        )
        assert response.status_code == 400, (
            f"Expected 400 for invalid expression {expression!r}, got {response.status_code}"
        )


def test_original_valid_evaluation():
    # Preserve the original verifier's specified frame-10 assertion.
    response = paced_post(
        headers=AUTH_HEADER,
        json={"expression": "R + G * B", "frame": 10},
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code} with body {response.text}"
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert data["result"] == 15050, f"Expected result 15050, got {data['result']}"


def test_many_frames_expressions_and_division_semantics():
    rng = random.SystemRandom()
    frames = rng.sample(range(100), 12)
    expressions = [
        lambda r, g, b: ("R + G * B", r + g * b),
        lambda r, g, b: ("R - G / 3 + B * 2", r - g / 3 + b * 2),
        lambda r, g, b: ("R / 7 + G / 5 - B / 11", r / 7 + g / 5 - b / 11),
        lambda r, g, b: ("12.5 + R * 2 - G", 12.5 + r * 2 - g),
        lambda r, g, b: ("B / 2 / 3 + R", b / 2 / 3 + r),
        lambda r, g, b: ("R - G - B", r - g - b),
        lambda r, g, b: ("100 / 4 + B - R * 3", 100 / 4 + b - r * 3),
    ]
    for index, frame in enumerate(frames):
        r, g, b = FRAMES[frame]
        expression, expected = expressions[index % len(expressions)](r, g, b)
        assert_result(expression, frame, expected)


def test_rate_limiting_by_actual_socket_ip():
    # Let all requests from prior tests expire. Do not assume X-Forwarded-For is trusted.
    time.sleep(1.3)
    status_codes = []
    for _ in range(10):
        response = requests.post(
            f"{BASE_URL}/evaluate",
            headers=AUTH_HEADER,
            json={"expression": "R + G", "frame": 10},
            timeout=5,
        )
        status_codes.append(response.status_code)

    success_count = status_codes.count(200)
    rate_limit_count = status_codes.count(429)
    assert success_count == 5, f"Expected exactly 5 successful requests, got {success_count}. Status codes: {status_codes}"
    assert rate_limit_count == 5, f"Expected exactly 5 rate-limited requests, got {rate_limit_count}. Status codes: {status_codes}"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
