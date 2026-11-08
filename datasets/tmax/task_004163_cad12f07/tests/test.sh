#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import time

import pytest

FRAMES_DIR = "/home/user/frames"
SERVER_SOURCE = "/home/user/serve_targets.c"
SERVER_BINARY = "/home/user/serve_targets"


def parse_pgm(path):
    """Parse a binary 8-bit P5 PGM and return (width, height, pixels)."""
    with open(path, "rb") as f:
        data = f.read()

    pos = 0

    def token():
        nonlocal pos
        while True:
            while pos < len(data) and data[pos] in b" \t\r\n\v\f":
                pos += 1
            if pos < len(data) and data[pos] == ord('#'):
                while pos < len(data) and data[pos] not in b"\r\n":
                    pos += 1
                continue
            break
        start = pos
        while pos < len(data) and data[pos] not in b" \t\r\n\v\f":
            pos += 1
        assert pos > start, f"Malformed PGM header in {path}"
        return data[start:pos]

    assert token() == b"P5", f"{path} is not a binary P5 PGM"
    try:
        width = int(token())
        height = int(token())
        maxval = int(token())
    except ValueError:
        pytest.fail(f"Malformed numeric PGM header in {path}")

    assert pos < len(data) and data[pos] in b" \t\r\n\v\f", \
        f"Missing raster separator in {path}"
    if data[pos:pos + 2] == b"\r\n":
        pos += 2
    else:
        pos += 1

    assert maxval == 255, f"{path} must be an 8-bit grayscale PGM"
    pixels = data[pos:]
    assert len(pixels) == width * height, \
        f"{path} has {len(pixels)} raster bytes, expected {width * height}"
    return width, height, pixels


@pytest.fixture(scope="session")
def reference_frames():
    with tempfile.TemporaryDirectory() as tmpdir:
        pattern = os.path.join(tmpdir, "frame_%03d.pgm")
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-i", "/app/input.mp4", "-vf", "scale=64:64,format=gray",
             "-vsync", "0", pattern],
            check=True,
        )
        refs = {}
        for name in sorted(os.listdir(tmpdir)):
            match = re.fullmatch(r"frame_(\d{3})\.pgm", name)
            if match:
                frame_id = int(match.group(1))
                refs[frame_id] = parse_pgm(os.path.join(tmpdir, name))[2]
        assert refs, "Reference extraction produced no frames"
        yield refs


def kill_port_8080_listeners():
    """Stop the agent-started listener so the submitted executable can be run directly."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(':', 1)[1], 16) == 8080 and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
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
                    victims.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.25)


def port_8080_is_listening():
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if (len(fields) >= 4 and fields[3] == "0A" and
                            int(fields[1].rsplit(':', 1)[1], 16) == 8080):
                        return True
        except FileNotFoundError:
            pass
    return False


@pytest.fixture(scope="session", autouse=True)
def run_submitted_server():
    assert os.path.isfile(SERVER_SOURCE), f"Missing C source: {SERVER_SOURCE}"
    assert os.path.isfile(SERVER_BINARY), f"Missing compiled server: {SERVER_BINARY}"
    mode = os.stat(SERVER_BINARY).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), \
        f"Server is not executable: {SERVER_BINARY}"
    with open(SERVER_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            f"{SERVER_BINARY} is not a compiled ELF executable"

    kill_port_8080_listeners()
    proc = subprocess.Popen(
        [SERVER_BINARY], cwd="/home/user",
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 5.0
    while time.time() < deadline and not port_8080_is_listening():
        if proc.poll() is not None:
            pytest.fail(f"Submitted server exited with status {proc.returncode}")
        time.sleep(0.05)
    assert port_8080_is_listening(), \
        "Submitted executable did not listen on 127.0.0.1:8080"
    assert proc.poll() is None, "Submitted server did not remain running"

    yield

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_frames_extracted_and_deleted(reference_frames):
    """Check extraction, P5 format, dimensions, content, and deletion of multiples of 5."""
    assert os.path.isdir(FRAMES_DIR), f"Frames directory does not exist: {FRAMES_DIR}"

    # Preserve the original checks for frames 1 through 20.
    for i in range(1, 21):
        frame_path = os.path.join(FRAMES_DIR, f"frame_{i:03d}.pgm")
        if i % 5 == 0:
            assert not os.path.exists(frame_path), \
                f"Frame {i} should have been deleted (multiple of 5)."
        else:
            assert os.path.exists(frame_path), \
                f"Frame {i} is missing. It should have been extracted."

    expected_ids = {i for i in reference_frames if i % 5 != 0}
    actual_ids = set()
    for name in os.listdir(FRAMES_DIR):
        match = re.fullmatch(r"frame_(\d{3})\.pgm", name)
        if match:
            actual_ids.add(int(match.group(1)))
    assert actual_ids == expected_ids, \
        f"Frame set differs from extracted video: expected {sorted(expected_ids)}, got {sorted(actual_ids)}"

    for frame_id in sorted(expected_ids):
        path = os.path.join(FRAMES_DIR, f"frame_{frame_id:03d}.pgm")
        width, height, pixels = parse_pgm(path)
        assert (width, height) == (64, 64), \
            f"Frame {frame_id} is {width}x{height}, expected 64x64"

        reference = reference_frames[frame_id]
        differences = [abs(a - b) for a, b in zip(pixels, reference)]
        mae = sum(differences) / len(differences)
        rmse = math.sqrt(sum(d * d for d in differences) / len(differences))
        assert mae <= 2.0 and rmse <= 6.0, \
            f"Frame {frame_id} does not match the corresponding extracted video frame"


def query_server(frame_id):
    """Helper to query the TCP server."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3.0)
    try:
        s.connect(('127.0.0.1', 8080))
        s.sendall(f"{frame_id}\n".encode('ascii'))
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
        data = b"".join(chunks).decode('ascii').strip()
    except ConnectionRefusedError:
        pytest.fail("Connection refused. Is the server running on 127.0.0.1:8080?")
    except socket.timeout:
        pytest.fail("Server timed out.")
    finally:
        s.close()
    return data


def test_server_nan_responses(reference_frames):
    """Test that the server responds with NaN for every deleted frame."""
    missing_ids = sorted(i for i in reference_frames if i % 5 == 0)
    for missing_id in missing_ids:
        response = query_server(missing_id)
        assert response == "NaN", \
            f"Expected 'NaN' for frame {missing_id}, got '{response}'"


def test_server_valid_responses(reference_frames):
    """Recompute and verify posterior means for every retained frame."""
    for valid_id in sorted(i for i in reference_frames if i % 5 != 0):
        response = query_server(valid_id)
        assert response != "NaN", \
            f"Expected a float for frame {valid_id}, got 'NaN'"

        try:
            val = float(response)
        except ValueError:
            pytest.fail(f"Response '{response}' for frame {valid_id} is not a valid float.")
        assert math.isfinite(val), f"Response '{response}' for frame {valid_id} is not finite"
        assert re.fullmatch(r"-?\d+\.\d{2}", response), \
            f"Response '{response}' does not have exactly two decimal places."

        frame_path = os.path.join(FRAMES_DIR, f"frame_{valid_id:03d}.pgm")
        _, _, pixels = parse_pgm(frame_path)
        pixel_mean = sum(pixels) / 4096.0
        posterior = ((128.0 / 50.0) + (pixel_mean / 10.0)) / \
                    ((1.0 / 50.0) + (1.0 / 10.0))
        expected = f"{posterior:.2f}"
        assert response == expected, \
            f"Frame {valid_id}: expected posterior {expected}, got {response}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
