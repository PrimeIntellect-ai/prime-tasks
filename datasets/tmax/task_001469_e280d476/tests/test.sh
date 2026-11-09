#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import socket
import stat
import subprocess

import pytest

HOST = "127.0.0.1"
PORT = 7777
WIDTH = 640
HEIGHT = 480
FRAME_BYTES = WIDTH * HEIGHT * 3
_source_frames = None


def request_server(request):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(10.0)
        try:
            s.connect((HOST, PORT))
        except Exception as e:
            pytest.fail(f"Failed to connect to server on {HOST}:{PORT} - {e}")
        s.sendall(request.encode("ascii"))
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
        return b"".join(chunks).decode("utf-8")


def source_frames():
    global _source_frames
    if _source_frames is None:
        raw = subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", "/app/recording.mp4",
            "-vf", "fps=1", "-frames:v", "10", "-pix_fmt", "rgb24",
            "-f", "rawvideo", "pipe:1"
        ])
        assert len(raw) >= 10 * FRAME_BYTES, "Could not decode all fixture video frames"
        _source_frames = [raw[i * FRAME_BYTES:(i + 1) * FRAME_BYTES] for i in range(10)]
    return _source_frames


def validate_jpeg_at_timestamp(path, second, comparison_second):
    with open(path, "rb") as f:
        data = f.read()
    assert data.startswith(b"\xff\xd8") and data.endswith(b"\xff\xd9"), f"{path} is not a JPEG file"

    probe = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height", "-of", "json", path
    ]))
    assert probe.get("streams"), f"{path} has no decodable image stream"
    stream = probe["streams"][0]
    assert stream.get("codec_name") == "mjpeg", f"{path} is not a JPEG image"
    assert (stream.get("width"), stream.get("height")) == (WIDTH, HEIGHT), "Extracted frame has wrong dimensions"

    decoded = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
        "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"
    ])
    assert len(decoded) == FRAME_BYTES, f"{path} did not decode to one complete frame"

    frames = source_frames()
    expected_error = sum(abs(a - b) for a, b in zip(decoded, frames[second])) / FRAME_BYTES
    other_error = sum(abs(a - b) for a, b in zip(decoded, frames[comparison_second])) / FRAME_BYTES
    assert expected_error < 8.0, f"JPEG pixels do not match the video frame at second {second}"
    assert expected_error + 0.5 < other_error, f"JPEG is not specific to the requested timestamp {second}"


def test_required_program_artifacts():
    source = "/app/server.c"
    binary = "/app/server"
    assert os.path.exists(source), f"{source} does not exist"
    assert stat.S_ISREG(os.lstat(source).st_mode), f"{source} is not a regular C source file"
    assert os.path.getsize(source) > 0, f"{source} is empty"
    with open(source, "rb") as f:
        source_data = f.read()
    assert b"\x00" not in source_data, f"{source} is not a text source file"

    assert os.path.exists(binary), f"{binary} does not exist"
    assert stat.S_ISREG(os.lstat(binary).st_mode), f"{binary} is not a regular compiled program"
    assert os.access(binary, os.X_OK), f"{binary} is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable"


def test_mount_and_restored_file():
    with open('/proc/mounts', 'r') as f:
        mounts = f.read()
    assert '/app/dataset' in mounts or '/app/cnc_data.ext4' in mounts, "The ext4 image is not mounted at /app/dataset"

    job_file = "/app/restored/job.gcode"
    assert os.path.exists(job_file), f"{job_file} does not exist"
    with open(job_file, 'r') as f:
        content = f.read()
    assert "; SYNC T=00:00:07 Z=3.5" in content, "The restored job.gcode does not contain the expected update.tar content"


def test_tcp_server_extract_success():
    frame_path = "/app/frames/frame_3.5.jpg"
    try:
        os.remove(frame_path)
    except FileNotFoundError:
        pass

    response = request_server("EXTRACT Z=3.5\n")
    match = re.match(r"^SUCCESS T=00:00:07 BYTES=(\d+)\n?$", response.strip())
    assert match is not None, f"Server response did not match expected success format. Got: {response}"
    bytes_reported = int(match.group(1))

    assert os.path.exists(frame_path), f"Frame image {frame_path} was not created"
    actual_size = os.path.getsize(frame_path)
    assert actual_size == bytes_reported, f"Reported size ({bytes_reported}) does not match actual file size ({actual_size})"
    validate_jpeg_at_timestamp(frame_path, 7, 2)


def test_tcp_server_extract_not_found():
    response = request_server("EXTRACT Z=9.9\n")
    assert response.strip() == "ERROR NOT_FOUND", f"Server response did not match expected error format. Got: {response}"


def test_server_parses_runtime_gcode_and_extracts_matching_frame():
    job_file = "/app/restored/job.gcode"
    with open(job_file, "rb") as f:
        original = f.read()

    existing = set(re.findall(rb"Z=([^\s]+)", original))
    while True:
        z = f"8{secrets.randbelow(1000000):06d}.{secrets.randbelow(1000):03d}"
        if z.encode() not in existing:
            break
    second = secrets.choice([1, 3, 5, 8])
    timestamp = f"00:00:{second:02d}"
    frame_path = f"/app/frames/frame_{z}.jpg"

    try:
        with open(job_file, "ab") as f:
            if original and not original.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"; SYNC T={timestamp} Z={z}\n".encode("ascii"))
        try:
            os.remove(frame_path)
        except FileNotFoundError:
            pass

        response = request_server(f"EXTRACT Z={z}\n")
        match = re.fullmatch(rf"SUCCESS T={re.escape(timestamp)} BYTES=(\d+)", response.strip())
        assert match is not None, f"Server did not parse the runtime-added synchronization entry. Got: {response}"
        assert os.path.exists(frame_path), f"Server did not create {frame_path}"
        assert os.path.getsize(frame_path) == int(match.group(1)), "Runtime extraction byte count is incorrect"
        validate_jpeg_at_timestamp(frame_path, second, 7)

        while True:
            missing_z = f"9{secrets.randbelow(1000000):06d}.{secrets.randbelow(1000):03d}"
            if missing_z.encode() not in existing and missing_z != z:
                break
        missing_response = request_server(f"EXTRACT Z={missing_z}\n")
        assert missing_response.strip() == "ERROR NOT_FOUND", "Server did not reject a runtime-generated absent Z-height"
    finally:
        with open(job_file, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
