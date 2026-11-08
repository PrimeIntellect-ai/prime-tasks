#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import stat
import subprocess
import concurrent.futures

import numpy as np
import pytest
import requests

WIDTH = 640
HEIGHT = 360
FRAME_SIZE = WIDTH * HEIGHT
EXPECTED = {}
EXPECTED_RAW = {}


def decode_reference_frames():
    cmd = [
        "ffmpeg", "-v", "error", "-i", "/app/sensor_data.mp4",
        "-vf", "format=gray", "-frames:v", "50",
        "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert proc.returncode == 0, f"Failed to decode reference video: {proc.stderr.decode(errors='replace')}"
    assert len(proc.stdout) == 50 * FRAME_SIZE, (
        f"Expected 50 decoded 640x360 grayscale frames, got {len(proc.stdout)} bytes"
    )

    weights = np.arange(1, WIDTH + 1, dtype=np.int64)
    for frame in range(1, 51):
        raw = proc.stdout[(frame - 1) * FRAME_SIZE:frame * FRAME_SIZE]
        pixels = np.frombuffer(raw, dtype=np.uint8).reshape(HEIGHT, WIDTH).astype(np.int64)
        EXPECTED_RAW[frame] = raw
        EXPECTED[frame] = int((pixels.sum(axis=0, dtype=np.int64) * weights).sum(dtype=np.int64))


def listening_analyzer_pids():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A" and fields[1].split(":")[-1].upper() == "2382":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    pids.append(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def test_00_compiled_server_and_extracted_frames_are_real():
    decode_reference_frames()

    assert os.path.isfile("/app/analyzer.c"), "Missing /app/analyzer.c"
    assert os.path.isfile("/app/analyzer"), "Missing compiled /app/analyzer"
    mode = os.stat("/app/analyzer").st_mode
    assert mode & stat.S_IXUSR, "/app/analyzer is not executable"
    with open("/app/analyzer", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/analyzer is not an ELF executable"

    pids = listening_analyzer_pids()
    assert pids, "No process is listening on port 9090"
    executables = []
    for pid in pids:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert "/app/analyzer" in executables, (
        f"Port 9090 is not served by /app/analyzer; listener executables: {executables}"
    )

    for frame in range(1, 51):
        path = f"/app/frames/frame_{frame}.gray"
        assert os.path.isfile(path), f"Missing extracted frame {path}"
        with open(path, "rb") as f:
            actual = f.read()
        assert len(actual) == FRAME_SIZE, f"{path} is not a 640x360 8-bit raw frame"
        assert actual == EXPECTED_RAW[frame], f"{path} does not match frame {frame} of sensor_data.mp4"


def test_01_server_math_and_response_format():
    for frame in range(1, 51):
        response = requests.get(
            f"http://localhost:9090/analyze?frame={frame}", timeout=5
        )
        assert response.status_code == 200, (
            f"Expected status 200 for frame {frame}, got {response.status_code}"
        )
        text = response.text.strip()
        assert re.fullmatch(r"-?[0-9]+\.[0-9]{6}", text), (
            f"Frame {frame} response is not formatted with %f: {response.text!r}"
        )
        assert text == f"{EXPECTED[frame]:.6f}", (
            f"Wrong weighted sum for frame {frame}: got {text}, expected {EXPECTED[frame]:.6f}"
        )


def test_02_visualize_script_executes_and_creates_outputs():
    path = "/app/visualize.py"
    assert os.path.isfile(path), f"Missing visualization script at {path}"

    for output in ("/app/results.csv", "/app/plot.png"):
        if os.path.lexists(output):
            os.remove(output)

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    proc = subprocess.run(
        ["python3", path], cwd="/app", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90,
    )
    assert proc.returncode == 0, (
        "visualize.py failed:\n"
        + proc.stdout.decode(errors="replace")
        + proc.stderr.decode(errors="replace")
    )
    assert os.path.isfile("/app/results.csv"), "visualize.py did not create /app/results.csv"
    assert os.path.isfile("/app/plot.png"), "visualize.py did not create /app/plot.png"


def test_results_csv_exists_and_format():
    path = "/app/results.csv"
    assert os.path.exists(path), f"Missing results file at {path}"

    with open(path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "results.csv is empty"
    assert rows[0] == ['frame', 'sum'], f"Unexpected header in results.csv: {rows[0]}"

    # 50 rows + header = 51 rows
    assert len(rows) == 51, f"Expected 51 rows (header + 50 frames) in results.csv, got {len(rows)}"

    for expected_frame, row in enumerate(rows[1:], start=1):
        assert len(row) == 2, f"Malformed CSV row for frame {expected_frame}: {row}"
        assert row[0] == str(expected_frame), (
            f"Expected frame {expected_frame} in results.csv, got {row[0]!r}"
        )
        try:
            value = float(row[1])
        except ValueError:
            pytest.fail(f"Invalid sum in results.csv for frame {expected_frame}: {row[1]!r}")
        assert value == float(EXPECTED[expected_frame]), (
            f"Wrong CSV sum for frame {expected_frame}: got {row[1]}, "
            f"expected {EXPECTED[expected_frame]:.6f}"
        )


def test_plot_png_exists():
    path = "/app/plot.png"
    assert os.path.exists(path), f"Missing plot file at {path}"
    assert os.path.getsize(path) > 0, f"Plot file {path} is empty"
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "plot.png is not a valid PNG file"
    import matplotlib.image as mpimg
    image = mpimg.imread(path)
    assert image.size > 0 and image.ndim in (2, 3), "plot.png could not be decoded as an image"


def test_server_endpoints():
    frames_to_test = [10, 25, 42]
    for frame in frames_to_test:
        url = f"http://localhost:9090/analyze?frame={frame}"
        try:
            response = requests.get(url, timeout=5)
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to server for frame {frame}: {e}")

        assert response.status_code == 200, f"Expected status 200 for frame {frame}, got {response.status_code}"

        try:
            val = float(response.text.strip())
        except ValueError:
            pytest.fail(f"Server response for frame {frame} is not a valid float: {response.text}")
        assert val == float(EXPECTED[frame]), (
            f"Incorrect weighted sum for frame {frame}: got {val}, expected {EXPECTED[frame]}"
        )


def test_server_determinism():
    url = "http://localhost:9090/analyze?frame=15"
    num_requests = 10

    def make_request():
        resp = requests.get(url, timeout=5)
        resp.raise_for_status()
        return resp.text.strip()

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(make_request) for _ in range(num_requests)]
        for future in concurrent.futures.as_completed(futures):
            try:
                results.append(future.result())
            except Exception as e:
                pytest.fail(f"Parallel request failed: {e}")

    assert len(results) == num_requests, "Not all requests completed successfully"

    first_result = results[0]
    for i, res in enumerate(results[1:], start=1):
        assert res == first_result, (
            f"Non-deterministic result detected! "
            f"Request 0 returned {first_result}, but Request {i} returned {res}"
        )
    assert first_result == f"{EXPECTED[15]:.6f}", (
        f"Deterministic but incorrect result for frame 15: {first_result}"
    )


def test_parallel_mixed_frames_are_correct():
    frames = [1, 7, 10, 15, 25, 33, 42, 50] * 3

    def make_request(frame):
        resp = requests.get(f"http://localhost:9090/analyze?frame={frame}", timeout=8)
        resp.raise_for_status()
        return frame, resp.text.strip()

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as executor:
        results = list(executor.map(make_request, frames))

    for frame, result in results:
        assert result == f"{EXPECTED[frame]:.6f}", (
            f"Incorrect result during parallel mixed-frame requests for frame {frame}: "
            f"got {result}, expected {EXPECTED[frame]:.6f}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
