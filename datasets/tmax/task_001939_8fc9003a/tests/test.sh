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
import json
import os
import shutil
import signal
import subprocess
import time

import pytest
import requests


def get_ground_truth_apds():
    truth_dir = "/tmp/truth_frames"
    shutil.rmtree(truth_dir, ignore_errors=True)
    os.makedirs(truth_dir, exist_ok=True)
    subprocess.run([
        "ffmpeg", "-y", "-i", "/app/video.mp4", "-vf", "fps=1",
        "-pix_fmt", "gray", f"{truth_dir}/frame_%04d.pgm"
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    frames = sorted(f for f in os.listdir(truth_dir) if f.endswith(".pgm"))
    apds = []
    prev_data = None

    for frame in frames:
        filepath = os.path.join(truth_dir, frame)
        with open(filepath, "rb") as f:
            data = f.read()

        tokens = []
        idx = 0
        while len(tokens) < 4:
            while idx < len(data) and data[idx:idx + 1].isspace():
                idx += 1
            if idx < len(data) and data[idx] == ord("#"):
                while idx < len(data) and data[idx] != ord("\n"):
                    idx += 1
                continue
            start = idx
            while idx < len(data) and not data[idx:idx + 1].isspace():
                idx += 1
            tokens.append(data[start:idx])

        pixel_data = data[idx + 1:]
        if prev_data is not None:
            total_diff = sum(abs(a - b) for a, b in zip(pixel_data, prev_data))
            apds.append(total_diff / len(pixel_data))
        prev_data = pixel_data

    return apds


@pytest.fixture(scope="session")
def apds():
    return get_ground_truth_apds()


@pytest.fixture(scope="session")
def ground_truth(apds):
    def _get_events(threshold):
        return [i + 2 for i, apd in enumerate(apds) if apd > threshold]
    return _get_events


def _kill_port_9090():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "2382" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def compiled_go_server():
    source = "/home/user/pipeline.go"
    assert os.path.isfile(source), f"{source} does not exist."
    binary = "/tmp/submitted_pipeline"
    build = subprocess.run(
        ["go", "build", "-o", binary, source],
        cwd="/home/user", text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=60
    )
    assert build.returncode == 0, f"pipeline.go is not a buildable Go program:\n{build.stdout}"

    _kill_port_9090()
    proc = subprocess.Popen(
        [binary], cwd="/home/user",
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Compiled pipeline.go exited before serving (exit code {proc.returncode})")
        try:
            requests.get("http://127.0.0.1:9090/api/events?threshold=0", timeout=0.4)
            break
        except requests.RequestException:
            time.sleep(0.2)
    else:
        proc.terminate()
        pytest.fail("Compiled pipeline.go did not start an HTTP server on 127.0.0.1:9090")

    yield
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_pipeline_go_exists():
    assert os.path.isfile("/home/user/pipeline.go"), "/home/user/pipeline.go does not exist."


def _raw_gray(path):
    return subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"
    ])


def test_extracted_png_frames_are_exact_1fps_grayscale_frames():
    frame_dir = "/tmp/frames"
    assert os.path.isdir(frame_dir), f"{frame_dir} does not exist"

    truth_png_dir = "/tmp/truth_png_frames"
    shutil.rmtree(truth_png_dir, ignore_errors=True)
    os.makedirs(truth_png_dir)
    subprocess.run([
        "ffmpeg", "-y", "-i", "/app/video.mp4", "-vf", "fps=1",
        "-pix_fmt", "gray", f"{truth_png_dir}/frame_%04d.png"
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    expected_names = sorted(f for f in os.listdir(truth_png_dir) if f.endswith(".png"))
    actual_names = sorted(f for f in os.listdir(frame_dir) if f.endswith(".png"))
    assert actual_names == expected_names, f"Expected PNG frames {expected_names}, got {actual_names}"

    for name in expected_names:
        actual = os.path.join(frame_dir, name)
        with open(actual, "rb") as f:
            assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{actual} is not a PNG file"
        pix_fmt = subprocess.check_output([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=pix_fmt", "-of", "default=nw=1:nk=1", actual
        ], text=True).strip()
        assert pix_fmt.startswith("gray"), f"{actual} is not grayscale (pixel format {pix_fmt})"
        expected = os.path.join(truth_png_dir, name)
        assert _raw_gray(actual) == _raw_gray(expected), f"{actual} does not match the required 1 fps video frame"


def test_experiments_jsonl(ground_truth):
    exp_file = "/home/user/experiments.jsonl"
    assert os.path.isfile(exp_file), f"{exp_file} does not exist."

    with open(exp_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {exp_file}, got {len(lines)}"

    results = {}
    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON line in {exp_file}: {line}")
        assert set(data.keys()) == {"threshold", "event_count"}, f"Expected exactly threshold and event_count keys: {line}"
        results[data["threshold"]] = data["event_count"]

    for t in [5, 10, 15, 20]:
        assert t in results, f"Missing threshold {t} in {exp_file}"
        expected_count = len(ground_truth(t))
        assert results[t] == expected_count, f"For threshold {t}, expected {expected_count} events, got {results[t]}"


def test_api_unauthorized():
    url = "http://127.0.0.1:9090/api/events?threshold=10"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized without API key, got {response.status_code}"

    response = requests.get(url, headers={"X-API-Key": "wrong-key"}, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized with incorrect API key, got {response.status_code}"


def assert_api_events(ground_truth, threshold):
    url = f"http://127.0.0.1:9090/api/events?threshold={repr(float(threshold))}"
    headers = {"X-API-Key": "etl-golang-video"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "events" in data, f"Missing 'events' key in response: {data}"
    expected_events = ground_truth(float(threshold))
    assert data["events"] == expected_events, f"Expected events {expected_events} for threshold {threshold}, got {data['events']}"


@pytest.mark.parametrize("threshold", [5, 15])
def test_api_events_authorized(ground_truth, threshold):
    assert_api_events(ground_truth, threshold)


def test_api_supports_dynamically_derived_float_thresholds(ground_truth, apds):
    distinct = sorted(set(apds))
    thresholds = [-0.125, max(distinct) + 0.625, 5.25, 10.5, 15.75, 20.125]
    thresholds.extend((a + b) / 2.0 for a, b in zip(distinct, distinct[1:]))

    seen = set()
    for threshold in thresholds:
        if threshold not in seen:
            seen.add(threshold)
            assert_api_events(ground_truth, threshold)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
