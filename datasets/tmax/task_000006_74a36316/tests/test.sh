#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_vision_math.py
import concurrent.futures
import http.client
import json
import math
import os
import secrets
import signal
import socket
import stat
import struct
import subprocess
import threading
import time

import pytest

ROOT = "/home/user/vision_math"
BINARY = os.path.join(ROOT, "server")
VIDEO = "/app/trajectory_test.mp4"
WIDTH = 320
HEIGHT = 240


def kill_port_owners(ports=(8080, 8081)):
    wanted = {f"{p:04X}" for p in ports}
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if fields[1].rsplit(":", 1)[-1].upper() in wanted:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.3)


def make_unpredictable_video(path):
    rng = secrets.SystemRandom()
    frames = []
    used = set()
    for _ in range(80):
        while True:
            left = rng.randrange(5, WIDTH - 15)
            top = rng.randrange(5, HEIGHT - 17)
            if (left, top) not in used:
                used.add((left, top))
                break
        frame = bytearray(WIDTH * HEIGHT)
        for y in range(top, top + 12):
            start = y * WIDTH + left
            frame[start:start + 10] = b"\xff" * 10
        frames.append(frame)

    cmd = [
        "ffmpeg", "-v", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "gray", "-s", f"{WIDTH}x{HEIGHT}",
        "-r", "25", "-i", "-", "-an", "-c:v", "libx264",
        "-preset", "ultrafast", "-qp", "0", "-pix_fmt", "yuv420p", path,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        for frame in frames:
            proc.stdin.write(frame)
        proc.stdin.close()
        rc = proc.wait(timeout=20)
    finally:
        if proc.poll() is None:
            proc.kill()
    assert rc == 0, "failed to generate verifier trajectory"


def compute_ground_truth(video_path):
    cmd = [
        "ffmpeg", "-v", "error", "-i", video_path, "-f", "image2pipe",
        "-vcodec", "rawvideo", "-pix_fmt", "gray", "-",
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    states = [(0.0, 0.0, 0.0, 0.0)]
    count = 0
    mean_x = mean_y = m2_x = m2_y = 0.0

    while True:
        frame = proc.stdout.read(WIDTH * HEIGHT)
        if len(frame) != WIDTH * HEIGHT:
            break
        sx = sy = bright_count = 0
        for idx, value in enumerate(frame):
            if value > 200:
                sx += idx % WIDTH
                sy += idx // WIDTH
                bright_count += 1
        if not bright_count:
            continue
        x = sx / bright_count
        y = sy / bright_count
        count += 1
        dx = x - mean_x
        dy = y - mean_y
        mean_x += dx / count
        mean_y += dy / count
        m2_x += dx * (x - mean_x)
        m2_y += dy * (y - mean_y)
        states.append((x, y, math.sqrt(m2_x / count), math.sqrt(m2_y / count)))

    assert proc.wait(timeout=10) == 0
    assert len(states) == 81, f"unexpected decoded frame count: {len(states)-1}"
    return states


def fetch_http(timeout=2):
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=timeout)
    try:
        conn.request("GET", "/latest")
        response = conn.getresponse()
        body = response.read()
        assert response.status == 200, f"HTTP status {response.status}"
        text = body.decode("utf-8")
        assert "nan" not in text.lower(), f"NaN found in response: {text}"
        data = json.loads(text, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
        for key in ("x", "y", "stddev_x", "stddev_y"):
            assert key in data, f"HTTP response missing {key}: {data}"
            assert isinstance(data[key], (int, float)) and math.isfinite(data[key])
        return tuple(float(data[k]) for k in ("x", "y", "stddev_x", "stddev_y"))
    finally:
        conn.close()


def fetch_tcp(timeout=2):
    with socket.create_connection(("127.0.0.1", 8081), timeout=timeout) as sock:
        sock.settimeout(timeout)
        payload = b""
        while len(payload) < 32:
            chunk = sock.recv(32 - len(payload))
            if not chunk:
                break
            payload += chunk
        assert len(payload) == 32, f"Expected 32 bytes, got {len(payload)}"
        assert sock.recv(1) == b"", "TCP server sent more than 32 bytes or did not close"
    values = struct.unpack("<dddd", payload)
    assert all(math.isfinite(v) for v in values), "non-finite TCP value"
    return values


def matching_state(value, states, tolerance):
    for index, expected in enumerate(states):
        if all(abs(a - b) <= tolerance for a, b in zip(value, expected)):
            return index
    return None


def test_service_endpoints_and_math():
    assert os.path.isfile(BINARY), "compiled server artifact is missing"
    mode = os.stat(BINARY).st_mode
    assert stat.S_ISREG(mode) and mode & 0o111, "server is not an executable regular file"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server must be the compiled ELF executable requested"

    kill_port_owners()
    make_unpredictable_video(VIDEO)
    states = compute_ground_truth(VIDEO)
    final_expected = states[-1]

    server = subprocess.Popen(
        [BINARY], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.monotonic() + 4
    first = None
    while time.monotonic() < deadline:
        assert server.poll() is None, f"server exited with status {server.returncode}"
        try:
            first = fetch_http(0.5)
            fetch_tcp(0.5)
            break
        except Exception:
            time.sleep(0.02)
    assert first is not None, "service did not listen on both required ports"

    observations = [("http", first)]
    errors = []
    lock = threading.Lock()
    stop = threading.Event()

    def sampler(kind):
        fetch = fetch_http if kind == "http" else fetch_tcp
        while not stop.is_set():
            try:
                value = fetch(1)
                with lock:
                    observations.append((kind, value))
            except Exception as exc:
                with lock:
                    errors.append(f"{kind}: {exc}")
            time.sleep(0.006)

    workers = [threading.Thread(target=sampler, args=(kind,), daemon=True)
               for kind in ("http", "http", "http", "tcp", "tcp", "tcp")]
    for worker in workers:
        worker.start()

    deadline = time.monotonic() + 7
    reached_final = False
    while time.monotonic() < deadline:
        assert server.poll() is None, f"server exited with status {server.returncode}"
        with lock:
            snapshot = list(observations)
        if any(matching_state(v, states, 2e-5 if kind == "http" else 1e-8) == len(states)-1
               for kind, v in snapshot):
            reached_final = True
            break
        time.sleep(0.03)

    stop.set()
    for worker in workers:
        worker.join(timeout=2)

    assert reached_final, "service never reached the final video state"
    assert not errors, "requests failed while video state was updating: " + "; ".join(errors[:5])

    observed_indices = set()
    for kind, value in observations:
        tolerance = 2e-5 if kind == "http" else 1e-8
        index = matching_state(value, states, tolerance)
        assert index is not None, f"{kind} returned a stale, fabricated, or torn state: {value}"
        observed_indices.add(index)
    assert len(observed_indices) >= 8, f"too few running states were exposed: {sorted(observed_indices)}"
    assert any(0 < i < len(states)-1 for i in observed_indices), "no intermediate running state was validated"

    # Preserve the original concurrent endpoint/load checks, now validating every field.
    num_requests = 50
    with concurrent.futures.ThreadPoolExecutor(max_workers=100) as pool:
        http_futures = [pool.submit(fetch_http) for _ in range(num_requests)]
        tcp_futures = [pool.submit(fetch_tcp) for _ in range(num_requests)]
        http_results = [future.result(timeout=4) for future in http_futures]
        tcp_results = [future.result(timeout=4) for future in tcp_futures]

    for value in http_results:
        assert matching_state(value, [final_expected], 2e-5) == 0, f"HTTP final state mismatch: {value}"
    for value in tcp_results:
        assert matching_state(value, [final_expected], 1e-8) == 0, f"TCP final state mismatch: {value}"

    gt_stddev_x, gt_stddev_y = final_expected[2], final_expected[3]
    final_http = {"x": http_results[-1][0], "y": http_results[-1][1],
                  "stddev_x": http_results[-1][2], "stddev_y": http_results[-1][3]}
    assert abs(final_http["stddev_x"] - gt_stddev_x) < 0.001
    assert abs(final_http["stddev_y"] - gt_stddev_y) < 0.001

    final_tcp = {"x": tcp_results[-1][0], "y": tcp_results[-1][1],
                 "stddev_x": tcp_results[-1][2], "stddev_y": tcp_results[-1][3]}
    assert abs(final_tcp["stddev_x"] - gt_stddev_x) < 0.001
    assert abs(final_tcp["stddev_y"] - gt_stddev_y) < 0.001
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_vision_math.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
