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
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import json
import os
import random
import signal
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:9090/metrics"
PROJECT = Path("/home/user/monitor-service")
EXPECTED_KEYS = {"uptime_status", "processed_frames", "anomalies_detected"}


def assert_metrics_response(response, frames=None, anomalies=None):
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/json"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert set(data) == EXPECTED_KEYS, f"Unexpected metrics structure: {data}"
    assert data.get("uptime_status") == "healthy", \
        f"Expected 'uptime_status' to be 'healthy', got {data.get('uptime_status')}"
    assert isinstance(data.get("processed_frames"), int) and not isinstance(data.get("processed_frames"), bool)
    assert isinstance(data.get("anomalies_detected"), int) and not isinstance(data.get("anomalies_detected"), bool)
    assert data["processed_frames"] >= 0
    assert data["anomalies_detected"] >= 0

    if frames is not None:
        assert data.get("processed_frames") == frames, \
            f"Expected 'processed_frames' to be {frames}, got {data.get('processed_frames')}"
    if anomalies is not None:
        assert data.get("anomalies_detected") == anomalies, \
            f"Expected 'anomalies_detected' to be {anomalies}, got {data.get('anomalies_detected')}"
    return data


def listening_inodes(port):
    wanted = f"{port:04X}"
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                result.add(fields[9])
    return result


def kill_port(port=9090):
    inodes = listening_inodes(port)
    if not inodes:
        return
    me = os.getpid()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == me:
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(proc.name), signal.SIGKILL)
                    break
        except (OSError, PermissionError):
            pass
    time.sleep(0.3)


def test_00_original_running_endpoint():
    try:
        response = requests.get(URL, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the monitoring service at {URL}. Is it running? Error: {exc}")
    # Preserve the original verifier's exact assertions for the supplied fixture.
    assert_metrics_response(response, frames=300, anomalies=4)


@pytest.fixture(scope="session")
def built_binary():
    assert (PROJECT / "Cargo.toml").is_file(), "Cargo.toml is missing"
    source = PROJECT / "src" / "main.rs"
    assert source.is_file() and source.stat().st_size > 0, "Rust source is missing"
    kill_port()
    result = subprocess.run(
        ["cargo", "build", "--quiet"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240
    )
    assert result.returncode == 0, f"The submitted Rust project does not build:\n{result.stdout}"
    binary = PROJECT / "target" / "debug" / "monitor-service"
    assert binary.is_file() and os.access(binary, os.X_OK), "Cargo did not produce the required executable"
    assert binary.read_bytes()[:4] == b"\x7fELF", "The produced artifact is not a native executable"
    return binary


@contextlib.contextmanager
def running_service(binary, args):
    kill_port()
    process = subprocess.Popen(
        [str(binary), *map(str, args)], cwd=PROJECT,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        deadline = time.time() + 25
        last_error = None
        while time.time() < deadline:
            if process.poll() is not None:
                pytest.fail(f"Service exited during video processing with status {process.returncode}")
            try:
                response = requests.get(URL, timeout=1)
                if response.status_code == 200:
                    break
            except requests.RequestException as exc:
                last_error = exc
            time.sleep(0.15)
        else:
            pytest.fail(f"Built service did not expose /metrics: {last_error}")
        yield
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        kill_port()


def make_video(path, frame_count):
    command = [
        "ffmpeg", "-v", "error", "-f", "lavfi",
        "-i", "testsrc=size=160x120:rate=25",
        "-frames:v", str(frame_count), "-threads", "1",
        "-pix_fmt", "yuv420p", "-c:v", "libx264",
        "-movflags", "+faststart", "-y", str(path),
    ]
    subprocess.run(command, check=True, timeout=90)


def decoded_frame_count(path):
    output = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
        "-show_entries", "stream=nb_read_frames", "-of", "json", str(path)
    ], text=True, timeout=30)
    streams = json.loads(output)["streams"]
    return int(streams[0]["nb_read_frames"])


def test_10_built_service_processes_default_fixture(built_binary):
    # Re-run the submitted artifact itself, rather than trusting a separately
    # launched process that could merely serve constants.
    with running_service(built_binary, []):
        response = requests.get(URL, timeout=5)
        assert_metrics_response(response, frames=300, anomalies=4)


def test_20_randomized_video_counts_and_concurrent_metrics(built_binary, tmp_path):
    # Frame counts are selected after the agent has finished, preventing a
    # constant 300 response from satisfying the frame-processing requirement.
    counts = [random.SystemRandom().randint(173, 257), random.SystemRandom().randint(389, 521)]
    if counts[0] == counts[1]:
        counts[1] += 17

    for index, requested_count in enumerate(counts):
        video = tmp_path / f"generated-{index}-{os.urandom(6).hex()}.mp4"
        make_video(video, requested_count)
        expected = decoded_frame_count(video)
        assert expected == requested_count

        with running_service(built_binary, [video]):
            def fetch(_):
                return requests.get(URL, timeout=5)

            with ThreadPoolExecutor(max_workers=12) as pool:
                responses = list(pool.map(fetch, range(36)))
            values = [assert_metrics_response(r, frames=expected) for r in responses]
            assert all(v == values[0] for v in values), "Concurrent metrics requests returned inconsistent counts"


def test_30_malformed_video_does_not_crash_service(built_binary, tmp_path):
    valid = tmp_path / "source.mp4"
    malformed = tmp_path / f"truncated-{os.urandom(6).hex()}.mp4"
    make_video(valid, 240)
    content = valid.read_bytes()
    malformed.write_bytes(content[: max(256, (len(content) * 2) // 3)])

    with running_service(built_binary, [malformed]):
        response = requests.get(URL, timeout=5)
        data = assert_metrics_response(response)
        assert data["processed_frames"] <= 240
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
