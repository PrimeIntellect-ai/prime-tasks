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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
SERVER = Path("/home/user/app/video_server.sh")
REGRESSION = Path("/home/user/app/regression_test.sh")


def wait_for_server(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(f"{BASE_URL}/frame?ts=0.1", timeout=2)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.2)
    return False


def test_server_is_running():
    assert SERVER.exists(), f"Daemon script not found at {SERVER}"
    assert os.access(SERVER, os.X_OK), f"Daemon script {SERVER} is not executable"
    first_line = SERVER.read_text(errors="replace").splitlines()[0]
    assert first_line.startswith("#!") and "bash" in first_line, "The daemon must remain a Bash program"

    try:
        requests.get(f"{BASE_URL}/frame?ts=0.1", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not listening on 127.0.0.1:8080")


def extract_frame(ts):
    response = requests.get(f"{BASE_URL}/frame?ts={ts}", timeout=10)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().split(";", 1)[0].strip() == "application/json"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /frame is not valid JSON")

    assert "time" in data, "JSON response missing 'time' key"
    assert "image" in data, "JSON response missing 'image' key"
    assert isinstance(data["time"], (int, float)) and not isinstance(data["time"], bool)
    assert abs(float(data["time"]) - float(ts)) < 1e-6, "Returned time does not match requested timestamp"
    assert isinstance(data["image"], str)

    try:
        decoded = base64.b64decode(data["image"], validate=True)
        assert len(decoded) > 0, "Decoded image is empty"
    except Exception as exc:
        pytest.fail(f"Image data is not valid strict base64: {exc}")

    assert decoded.startswith(b"\xff\xd8") and decoded.endswith(b"\xff\xd9"), "Image is not a JPEG"
    return decoded


def decode_rgb(jpeg):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        input=jpeg,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0 and result.stdout, "Returned JPEG cannot be decoded by ffmpeg"
    assert len(result.stdout) == 320 * 240 * 3, "Returned frame has unexpected dimensions"
    return result.stdout


def reference_rgb(ts):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", str(ts), "-i", "/app/surveillance.mp4",
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0 and len(result.stdout) == 320 * 240 * 3
    return result.stdout


def mean_abs(a, b):
    assert len(a) == len(b)
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def test_frame_endpoint():
    image_at_2 = decode_rgb(extract_frame(2.0))
    image_at_7 = decode_rgb(extract_frame(7.0))
    ref_2 = reference_rgb(2.0)
    ref_7 = reference_rgb(7.0)

    own_2 = mean_abs(image_at_2, ref_2)
    wrong_2 = mean_abs(image_at_2, ref_7)
    own_7 = mean_abs(image_at_7, ref_7)
    wrong_7 = mean_abs(image_at_7, ref_2)
    assert own_2 < 15 and own_2 + 5 < wrong_2, "Frame does not correspond to ts=2.0"
    assert own_7 < 15 and own_7 + 5 < wrong_7, "Frame does not correspond to ts=7.0"


def timestamp_candidates(entry):
    candidates = []

    def visit(value, timestamp_context=False):
        if isinstance(value, bool) or value is None:
            return
        if isinstance(value, dict):
            for key, child in value.items():
                key_l = str(key).lower()
                relevant = any(part in key_l for part in ("timestamp", "micros", "time", "ts"))
                visit(child, timestamp_context or relevant)
        elif isinstance(value, list):
            for child in value:
                visit(child, timestamp_context)
        elif isinstance(value, (int, float)):
            number = int(value)
            if timestamp_context or number >= 1_000_000_000_000:
                candidates.append(number)
        elif isinstance(value, str):
            for match in re.findall(r"(?<!\d)(\d{13,17})(?!\d)", value):
                candidates.append(int(match))

    visit(entry)
    return candidates


def test_logs_endpoint_valid_json():
    # Preserve the original explicit large-value regression assertion.
    response = requests.get(
        f"{BASE_URL}/logs?start=2147483647000&end=2147484000000", timeout=5
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().split(";", 1)[0].strip() == "application/json"
    try:
        logs = response.json()
    except ValueError:
        pytest.fail("Response from /logs is not valid JSON. The JSON serialization issue might not be fixed.")
    assert isinstance(logs, list), "Expected logs to be a JSON array"

    # Generate access records at real microsecond timestamps, which are far above
    # the 32-bit signed range, and retain disjoint wall-clock windows for them.
    windows = []
    start = time.time_ns() // 1000 - 100_000
    for index, frame_ts in enumerate((1.0, 1.5, 2.5)):
        before = time.time_ns() // 1000
        marker = f"audit_{os.getpid()}_{index}_quote%22_slash%5C"
        frame_response = requests.get(
            f"{BASE_URL}/frame?ts={frame_ts}&marker={marker}", timeout=10
        )
        assert frame_response.status_code == 200
        time.sleep(0.08)
        after = time.time_ns() // 1000
        windows.append((before, after))
        time.sleep(0.04)
    end = time.time_ns() // 1000 + 100_000

    response = requests.get(f"{BASE_URL}/logs?start={start}&end={end}", timeout=10)
    assert response.status_code == 200
    assert response.headers.get("Content-Type", "").lower().split(";", 1)[0].strip() == "application/json"
    try:
        logs = response.json()
    except ValueError:
        pytest.fail("Logs containing quoted/backslash request data are not strict valid JSON")
    assert isinstance(logs, list), "Expected logs to be a JSON array"
    assert len(logs) >= 3, "Generated frame accesses are missing from the requested timeline"

    ordered_timestamps = []
    for entry in logs:
        in_range = [ts for ts in timestamp_candidates(entry) if start <= ts <= end]
        assert in_range, f"Log entry has no in-range microsecond timestamp: {entry!r}"
        ordered_timestamps.append(min(in_range))

    assert ordered_timestamps == sorted(ordered_timestamps), "Logs are not chronologically ordered"
    assert all(start <= ts <= end for ts in ordered_timestamps), "Logs outside requested bounds were returned"
    for before, after in windows:
        assert any(before <= ts <= after for ts in ordered_timestamps), "A generated access log was omitted"

    # A strict subrange must neither leak entries outside its bounds nor ignore
    # the large microsecond start/end comparisons.
    narrow_start, narrow_end = windows[1]
    narrow_response = requests.get(
        f"{BASE_URL}/logs?start={narrow_start}&end={narrow_end}", timeout=10
    )
    assert narrow_response.status_code == 200
    narrow_logs = narrow_response.json()
    assert isinstance(narrow_logs, list) and narrow_logs
    narrow_times = []
    for entry in narrow_logs:
        matches = [ts for ts in timestamp_candidates(entry) if narrow_start <= ts <= narrow_end]
        assert matches, "Narrow logs query returned an out-of-bounds entry"
        narrow_times.append(min(matches))
    assert narrow_times == sorted(narrow_times)


def stop_listener():
    subprocess.run(["fuser", "-k", "8080/tcp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "nc.*8080"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "socat.*8080"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            requests.get(BASE_URL, timeout=0.2)
        except requests.exceptions.RequestException:
            return
        time.sleep(0.1)


def test_regression_test_script():
    assert REGRESSION.exists(), f"Regression test script not found at {REGRESSION}"
    assert os.access(REGRESSION, os.X_OK), f"Regression test script {REGRESSION} is not executable"
    first_line = REGRESSION.read_text(errors="replace").splitlines()[0]
    assert first_line.startswith("#!"), "Regression test must be an executable script"

    # Preserve the original success assertion against the submitted daemon.
    result = subprocess.run([str(REGRESSION)], capture_output=True, text=True, timeout=240)
    assert result.returncode == 0, (
        f"Regression test script failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )

    # Replace the daemon temporarily with a controlled server that grows by 1MB
    # per frame request. A genuine regression test must send at least 100 requests
    # and must exit exactly 1 after observing growth greater than 5MB.
    original = SERVER.read_bytes()
    original_mode = SERVER.stat().st_mode
    fake_count = Path("/tmp/regression_fake_count")
    fake_count.unlink(missing_ok=True)
    fake_process = None
    try:
        stop_listener()
        SERVER.write_text(r'''#!/usr/bin/python3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json

held = []
count = 0
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        if self.path.startswith('/frame?ts=0.5'):
            block = bytearray(1024 * 1024)
            for i in range(0, len(block), 4096):
                block[i] = 1
            held.append(block)
            count += 1
            Path('/tmp/regression_fake_count').write_text(str(count))
            body = json.dumps({'time': 0.5, 'image': '/9j/2Q=='}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
''')
        os.chmod(SERVER, 0o755)
        fake_process = subprocess.Popen(
            [str(SERVER)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                requests.get(f"{BASE_URL}/", timeout=0.5)
                break
            except requests.exceptions.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail("Could not start controlled leak server")

        failure_result = subprocess.run(
            [str(REGRESSION)], capture_output=True, text=True, timeout=240
        )
        count = int(fake_count.read_text()) if fake_count.exists() else 0
        assert count >= 100, f"Regression script sent only {count} matching frame requests"
        assert failure_result.returncode == 1, (
            "Regression script did not report the controlled >5MB memory growth with exit code 1.\n"
            f"STDOUT:\n{failure_result.stdout}\nSTDERR:\n{failure_result.stderr}"
        )
    finally:
        if fake_process is not None:
            try:
                os.killpg(fake_process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                fake_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        stop_listener()
        SERVER.write_bytes(original)
        os.chmod(SERVER, original_mode)
        subprocess.Popen(
            [str(SERVER)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        assert wait_for_server(), "Submitted daemon did not restart after regression test validation"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
