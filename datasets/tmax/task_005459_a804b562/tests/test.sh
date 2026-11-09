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
import os
import re
import subprocess
import pytest
import requests


def get_expected_anomalies(video_path="/app/monitoring.mp4"):
    """Derive expected anomalies from signalstats metadata."""
    cmd = [
        "ffmpeg", "-nostdin", "-i", video_path,
        "-vf", "signalstats,metadata=mode=print:key=lavfi.signalstats.YAVG",
        "-f", "null", "-",
    ]
    result = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed while deriving expected metrics: {result.stderr}")

    frames = []
    current_frame = None
    for line in result.stderr.splitlines():
        frame_match = re.search(r"frame:\s*(\d+)", line)
        if frame_match:
            current_frame = int(frame_match.group(1))

        yavg_match = re.search(
            r"lavfi\.signalstats\.YAVG=([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
            line,
        )
        if yavg_match and current_frame is not None:
            frames.append((current_frame, float(yavg_match.group(1))))
            current_frame = None

    if not frames:
        raise AssertionError("ffmpeg produced no parseable frame/YAVG metadata")

    frames.sort(key=lambda x: x[0])

    imputed_yavg = []
    for i in range(len(frames)):
        _, yavg = frames[i]
        if yavg == 0.0:
            prev_y = next(
                (frames[j][1] for j in range(i - 1, -1, -1) if frames[j][1] != 0.0),
                None,
            )
            next_y = next(
                (frames[j][1] for j in range(i + 1, len(frames)) if frames[j][1] != 0.0),
                None,
            )
            if prev_y is not None and next_y is not None:
                yavg = (prev_y + next_y) / 2.0
            elif prev_y is not None:
                yavg = prev_y
            elif next_y is not None:
                yavg = next_y
        imputed_yavg.append(yavg)

    anomalies = []
    for i in range(1, len(frames)):
        diff = abs(imputed_yavg[i] - imputed_yavg[i - 1])
        if diff > 50.0:
            anomalies.append((frames[i][0], diff))

    return anomalies


def test_anomalies_csv():
    """Validate that the CSV file contains the derived anomalies."""
    expected = get_expected_anomalies()
    assert expected, "The generated monitoring video should contain anomalies"

    csv_path = "/home/user/anomalies.csv"
    assert os.path.exists(csv_path), f"CSV file not found: {csv_path}"

    actual = []
    with open(csv_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid CSV line format: '{line}'"
            actual.append((int(parts[0]), float(parts[1])))

    assert len(actual) == len(expected), (
        f"Expected {len(expected)} anomalies, but found {len(actual)}"
    )

    for (act_n, act_diff), (exp_n, exp_diff) in zip(actual, expected):
        assert act_n == exp_n, f"Expected frame number {exp_n}, got {act_n}"
        assert abs(act_diff - exp_diff) < 1e-2, (
            f"Expected difference {exp_diff} for frame {exp_n}, got {act_diff}"
        )


def test_http_server():
    """Validate that the server accepts multiple requests and serves the CSV."""
    url = "http://127.0.0.1:8080/anomalies"
    csv_path = "/home/user/anomalies.csv"
    assert os.path.exists(csv_path), f"CSV file not found: {csv_path}"

    with open(csv_path, "rb") as f:
        expected_bytes = f.read()
    expected_content = expected_bytes.decode().strip()

    for request_number in range(1, 4):
        try:
            response = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(
                f"Request {request_number} failed to connect to the HTTP server at {url}: {e}"
            )

        assert response.status_code == 200, (
            f"Request {request_number}: expected HTTP 200 OK, got {response.status_code}"
        )
        actual_content = response.text.strip()
        assert actual_content == expected_content, (
            "HTTP response body does not match the exact contents of anomalies.csv"
        )
        assert response.content == expected_bytes, (
            "HTTP response body bytes do not exactly match anomalies.csv"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
