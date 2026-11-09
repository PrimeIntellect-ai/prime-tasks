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
import io
import os
import re
import stat
import tarfile
import socket
import subprocess
import tempfile
from functools import lru_cache

import cv2
import numpy as np
import pytest
import requests
from PIL import Image

VIDEO_PATH = "/app/status_light.mp4"


def frame_color(frame):
    b, g, r = frame.mean(axis=(0, 1))
    if r > g + 50 and r > b + 50:
        return "red"
    if g > r + 50 and g > b + 50:
        return "green"
    return "other"


@lru_cache(maxsize=1)
def expected_video_data():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open video: {VIDEO_PATH}"
    total = red = green = 0
    dimensions = None
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            total += 1
            dimensions = (frame.shape[1], frame.shape[0])
            color = frame_color(frame)
            assert color != "other", f"Video frame {total} is neither red nor green"
            red += color == "red"
            green += color == "green"
    finally:
        cap.release()

    assert total > 0, "Video contains no decodable frames"
    assert red + green == total
    return {
        "total": total,
        "red": red,
        "green": green,
        "dimensions": dimensions,
        "uptime": f"{green * 100.0 / total:.2f}",
    }


def test_downtime_backup():
    """Verify the archive contains exactly all decodable red video frames and no other files."""
    expected = expected_video_data()
    archive_path = "/home/user/downtime_backup.tar.gz"
    assert os.path.exists(archive_path), f"Archive not found: {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"Not a valid tar archive: {archive_path}"

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        for member in members:
            assert not os.path.isabs(member.name), f"Archive contains absolute path: {member.name}"
            assert ".." not in member.name.split("/"), f"Archive contains unsafe path: {member.name}"
            assert member.isdir() or member.isfile(), f"Archive contains non-file member: {member.name}"

        files = [member for member in members if member.isfile()]
        assert len(files) == expected["red"], (
            f"Expected exactly {expected['red']} red frame files, found {len(files)}"
        )

        for member in files:
            assert member.name.lower().endswith(".png"), f"Non-PNG file in archive: {member.name}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member: {member.name}"
            payload = extracted.read()
            try:
                with Image.open(io.BytesIO(payload)) as image:
                    assert image.format == "PNG", f"File is not actually PNG: {member.name}"
                    image.load()
                    assert image.size == expected["dimensions"], (
                        f"Wrong frame dimensions for {member.name}: {image.size}"
                    )
                    rgb = np.asarray(image.convert("RGB"))
            except Exception as exc:
                pytest.fail(f"Undecodable PNG {member.name}: {exc}")

            r, g, b = rgb.mean(axis=(0, 1))
            assert r > g + 50 and r > b + 50, f"Archived frame is not red: {member.name}"


def test_expect_script():
    """Run the expect script against an instrumented alert and verify its actual interaction."""
    expected = expected_video_data()["uptime"]
    script_path = "/home/user/alert.exp"
    trigger_path = "/app/trigger_alert.sh"
    assert os.path.isfile(script_path), f"Expect script not found: {script_path}"

    with open(script_path, "r", encoding="utf-8", errors="replace") as source_file:
        source = source_file.read()
    assert re.search(r"(?m)^\s*spawn\s+(?:--\s+)?/app/trigger_alert\.sh(?:\s|$)", source), (
        "Expect script must spawn /app/trigger_alert.sh"
    )

    with open(trigger_path, "rb") as original_file:
        original = original_file.read()
    original_mode = stat.S_IMODE(os.stat(trigger_path).st_mode)

    fd, log_path = tempfile.mkstemp(prefix="alert-input-", dir="/tmp")
    os.close(fd)
    os.unlink(log_path)
    replacement = f'''#!/bin/bash
echo -n "Enter server uptime percentage:"
IFS= read -r UPTIME
echo -n "Confirm alert dispatch (y/n):"
IFS= read -r CONFIRM
printf '%s\\n%s\\n' "$UPTIME" "$CONFIRM" > {log_path!r}
if [ "$UPTIME" = "{expected}" ] && [ "$CONFIRM" = "y" ]; then
    echo "Alert dispatched successfully."
    exit 0
fi
echo "Alert failed."
exit 1
'''

    try:
        with open(trigger_path, "w", encoding="utf-8") as replacement_file:
            replacement_file.write(replacement)
        os.chmod(trigger_path, 0o755)

        try:
            result = subprocess.run(
                ["expect", script_path], capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Expect script timed out.")

        assert result.returncode == 0, (
            f"Expect script failed with exit code {result.returncode}. Output: {result.stdout}"
        )
        assert "Alert dispatched successfully." in result.stdout, (
            f"Alert was not dispatched successfully. Output: {result.stdout}"
        )
        assert os.path.exists(log_path), "Expect script did not interact with /app/trigger_alert.sh"
        with open(log_path, "r", encoding="utf-8") as input_log:
            supplied = input_log.read().splitlines()
        assert supplied == [expected, "y"], (
            f"Expected uptime {expected} followed by y, received {supplied}"
        )
    finally:
        with open(trigger_path, "wb") as original_file:
            original_file.write(original)
        os.chmod(trigger_path, original_mode)
        if os.path.exists(log_path):
            os.unlink(log_path)


def test_http_service():
    """Verify the HTTP service returns the uptime derived from the video."""
    expected = float(expected_video_data()["uptime"])
    url = "http://127.0.0.1:8080/api/status"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"HTTP request failed: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert isinstance(data, dict), f"Expected a JSON object, got: {data}"
    assert set(data) == {"uptime_percent"}, f"Unexpected JSON payload: {data}"
    uptime = float(data["uptime_percent"])
    assert uptime == expected, f"Expected uptime_percent {expected:.2f}, got {uptime}"


def test_tcp_service():
    """Verify the TCP service returns the derived uptime and closes the connection."""
    expected_response = f"UPTIME:{expected_video_data()['uptime']}\n".encode()
    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=2) as sock:
            sock.settimeout(2)
            chunks = []
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                chunks.append(chunk)
    except (socket.timeout, ConnectionRefusedError, OSError) as exc:
        pytest.fail(f"TCP connection failed or was not closed: {exc}")

    data = b"".join(chunks)
    assert data == expected_response, f"Expected TCP response {expected_response!r}, got {data!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
