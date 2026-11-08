#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import signal
import socket
import subprocess
import time

import pytest

FRAMES_DIR = "/home/user/frames"
CSV_PATH = "/home/user/etl/embeddings.csv"
EMBED_SOURCE = "/home/user/etl/embed.c"
SERVER_SOURCE = "/home/user/etl/server.c"
VIDEO_PATH = "/app/surveillance.mp4"
HOST = "127.0.0.1"
PORT = 9090
FRAME_SIZE = 320 * 240 * 3


def compute_expected_embedding(raw_bytes):
    assert len(raw_bytes) == FRAME_SIZE
    cells = [0.0] * 16
    for y in range(240):
        for x in range(320):
            idx = (y * 320 + x) * 3
            r = raw_bytes[idx]
            g = raw_bytes[idx + 1]
            b = raw_bytes[idx + 2]
            gray = 0.299 * r + 0.587 * g + 0.114 * b
            cell_x = x // 80
            cell_y = y // 60
            cell_idx = cell_y * 4 + cell_x
            cells[cell_idx] += gray
    for i in range(16):
        cells[i] /= 80 * 60
    return cells


@pytest.fixture(scope="session")
def authoritative_frames(tmp_path_factory):
    output = tmp_path_factory.mktemp("reference") / "frames.rgb"
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", VIDEO_PATH,
            "-t", "10", "-vf", "fps=1,scale=320:240",
            "-frames:v", "10", "-pix_fmt", "rgb24",
            "-f", "rawvideo", str(output),
        ],
        check=True,
    )
    data = output.read_bytes()
    assert len(data) == 10 * FRAME_SIZE, "Reference extraction did not produce exactly 10 frames"
    return [data[i * FRAME_SIZE:(i + 1) * FRAME_SIZE] for i in range(10)]


def test_frames_extracted(authoritative_frames):
    assert os.path.exists(FRAMES_DIR), f"Directory {FRAMES_DIR} does not exist."
    for i in range(1, 11):
        frame_name = f"frame_{i:02d}.raw"
        frame_path = os.path.join(FRAMES_DIR, frame_name)
        assert os.path.exists(frame_path), f"Frame {frame_name} missing."
        assert os.path.isfile(frame_path), f"Frame {frame_name} is not a regular file."
        assert os.path.getsize(frame_path) == 230400, f"Frame {frame_name} has incorrect size."
        with open(frame_path, "rb") as f:
            actual = f.read()
        assert actual == authoritative_frames[i - 1], f"Frame {frame_name} was not correctly extracted from {VIDEO_PATH}."


def test_c_sources_compile(tmp_path):
    assert os.path.isfile(EMBED_SOURCE), f"C source {EMBED_SOURCE} missing."
    assert os.path.isfile(SERVER_SOURCE), f"C source {SERVER_SOURCE} missing."
    assert os.path.getsize(EMBED_SOURCE) > 0, f"C source {EMBED_SOURCE} is empty."
    assert os.path.getsize(SERVER_SOURCE) > 0, f"C source {SERVER_SOURCE} is empty."
    subprocess.run(["gcc", "-O2", EMBED_SOURCE, "-lm", "-o", str(tmp_path / "embed")], check=True)
    subprocess.run(["gcc", "-O2", SERVER_SOURCE, "-lm", "-o", str(tmp_path / "server")], check=True)


def test_embeddings_csv(authoritative_frames):
    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} missing."
    frame_01_path = os.path.join(FRAMES_DIR, "frame_01.raw")
    with open(frame_01_path, "rb") as f:
        raw_bytes = f.read()
    expected_emb = compute_expected_embedding(raw_bytes)

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")

    frame_01_line = None
    for line in lines:
        if line.startswith("frame_01.raw"):
            frame_01_line = line
            break
    assert frame_01_line is not None, "frame_01.raw not found in embeddings.csv"
    parts = frame_01_line.split(",")
    assert len(parts) == 17, "embeddings.csv line should have 17 columns (filename + 16 values)"
    for i in range(16):
        actual_val = float(parts[i + 1])
        expected_val = expected_emb[i]
        assert abs(actual_val - expected_val) <= 0.05, f"Embedding value {i} mismatch for frame_01.raw: expected ~{expected_val:.2f}, got {actual_val}"

    expected_header = ["filename"] + [f"v{i}" for i in range(16)]
    assert lines[0].split(",") == expected_header, "embeddings.csv has an incorrect header"
    assert len(lines) == 11, "embeddings.csv must contain one header and exactly 10 data rows"

    rows = {}
    two_decimal = re.compile(r"^-?\d+\.\d{2}$")
    for line in lines[1:]:
        fields = line.split(",")
        assert len(fields) == 17, "Every embeddings.csv data row must have 17 columns"
        name = fields[0]
        assert name not in rows, f"Duplicate CSV row for {name}"
        assert all(two_decimal.fullmatch(value) for value in fields[1:]), "Embedding values must be rounded to exactly 2 decimal places"
        rows[name] = [float(value) for value in fields[1:]]

    expected_names = [f"frame_{i:02d}.raw" for i in range(1, 11)]
    assert set(rows) == set(expected_names), "CSV must contain exactly one row for each extracted frame"
    for i, name in enumerate(expected_names):
        expected = compute_expected_embedding(authoritative_frames[i])
        for j, actual in enumerate(rows[name]):
            assert math.isfinite(actual), f"Non-finite embedding value for {name}"
            assert abs(actual - expected[j]) <= 0.011, f"Embedding value {j} mismatch for {name}: expected {expected[j]:.2f}, got {actual}"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_server():
    pids = listener_pids(PORT)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(PORT):
        time.sleep(0.05)
    for pid in listener_pids(PORT):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(PORT):
        time.sleep(0.05)
    assert not listener_pids(PORT), "Could not stop the existing listener on port 9090"


def wait_for_server(process):
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Compiled server exited with status {process.returncode}")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("Compiled server did not bind to 127.0.0.1:9090")


def nearest_name(query, rows):
    return min(
        rows,
        key=lambda name: sum((query[i] - rows[name][i]) ** 2 for i in range(16)),
    )


def test_tcp_server(authoritative_frames, tmp_path):
    frame_03_path = os.path.join(FRAMES_DIR, "frame_03.raw")
    assert os.path.exists(frame_03_path), "frame_03.raw missing, cannot test server properly."
    with open(frame_03_path, "rb") as f:
        raw_bytes = f.read()
    expected_emb = compute_expected_embedding(raw_bytes)

    server_binary = tmp_path / "verified_server"
    subprocess.run(["gcc", "-O2", SERVER_SOURCE, "-lm", "-o", str(server_binary)], check=True)
    stop_existing_server()
    process = subprocess.Popen(
        [str(server_binary)],
        cwd="/home/user/etl",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server(process)

    rows = {
        f"frame_{i:02d}.raw": [round(v, 2) for v in compute_expected_embedding(authoritative_frames[i - 1])]
        for i in range(1, 11)
    }

    queries = []
    queries.append((expected_emb, "frame_03.raw"))
    for name, vector in rows.items():
        queries.append((vector, name))
    rng = random.Random(9090)
    for _ in range(12):
        query = [rng.uniform(0.0, 255.0) for _ in range(16)]
        queries.append((query, nearest_name(query, rows)))

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        try:
            s.connect((HOST, PORT))
        except Exception as e:
            pytest.fail(f"Failed to connect to TCP server at {HOST}:{PORT}: {e}")

        try:
            stream = s.makefile("rb")
            for query, expected_name in queries:
                query_str = "SEARCH " + ",".join(f"{v:.6f}" for v in query) + "\n"
                s.sendall(query_str.encode("utf-8"))
                response = stream.readline()
                assert response == f"MATCH {expected_name}\n".encode(), f"Expected MATCH {expected_name}, got {response!r}"

            s.sendall(b"QUIT\n")
            resp = stream.readline()
            assert resp == b"", "Connection should be closed after QUIT"
        finally:
            s.close()
    except Exception:
        if process.poll() is None:
            process.terminate()
        raise
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
