#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import tempfile
import hashlib
import struct
import pytest


def test_frames_extracted():
    frames_dir = "/home/user/frames"
    assert os.path.isdir(frames_dir), f"Directory missing: {frames_dir}"

    frames = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    assert frames, "No frames extracted"

    # Derive the exact expected output independently from the supplied video.
    with tempfile.TemporaryDirectory() as expected_dir:
        pattern = os.path.join(expected_dir, "frame_%03d.png")
        subprocess.run([
            "ffmpeg", "-v", "error", "-i", "/app/screencast.mp4",
            "-vf", "fps=1/5", pattern
        ], check=True)
        expected = sorted(f for f in os.listdir(expected_dir) if f.endswith(".png"))
        assert frames == expected, "Frame names/count do not match extraction at five-second intervals"
        for name in expected:
            with open(os.path.join(frames_dir, name), "rb") as actual_file, \
                 open(os.path.join(expected_dir, name), "rb") as expected_file:
                assert hashlib.sha256(actual_file.read()).digest() == hashlib.sha256(expected_file.read()).digest(), \
                    f"Frame {name} was not correctly extracted from the video"


def test_frames_manifest():
    manifest_path = "/home/user/frames_manifest.txt"
    frames_dir = "/home/user/frames"
    assert os.path.isfile(manifest_path), f"Manifest missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        lines = f.read().strip().split("\n")

    frames = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    assert len(lines) == len(frames), "Manifest line count does not match frame count"

    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Malformed manifest line: {line}"
        hash_val, filename = parts
        frame_path = os.path.join(frames_dir, filename)
        assert os.path.isfile(frame_path), f"File in manifest not found: {filename}"
        with open(frame_path, "rb") as frame_file:
            actual_hash = hashlib.sha256(frame_file.read()).hexdigest()
        assert hash_val == actual_hash, f"Hash mismatch for {filename}"


def test_filtered_docs():
    raw_dir = "/home/user/docs_raw"
    filtered_dir = "/home/user/filtered_docs"
    assert os.path.isdir(filtered_dir), f"Directory missing: {filtered_dir}"

    raw_files = [f for f in os.listdir(raw_dir) if f.endswith(".md")]
    expected_files = [f for f in raw_files if os.path.getsize(os.path.join(raw_dir, f)) > 512]
    filtered_files = [f for f in os.listdir(filtered_dir) if f.endswith(".md")]
    assert sorted(filtered_files) == sorted(expected_files), "Filtered docs do not match expected files > 512 bytes"

    for name in expected_files:
        with open(os.path.join(raw_dir, name), "rb") as f1, \
             open(os.path.join(filtered_dir, name), "rb") as f2:
            assert f1.read() == f2.read(), f"Content mismatch for {name}"


def expected(data):
    if len(data) < 7 or data[:4] != b"TDOC" or data[4] != 1:
        return 1, b"INVALID_HEADER\n"
    count = int.from_bytes(data[5:7], "little")
    pos = 7
    out = bytearray()
    for _ in range(count):
        if pos + 8 > len(data):
            out.extend(b"TRUNCATED\n")
            return 2, bytes(out)
        ts, doc_id, content_len = struct.unpack_from("<IHH", data, pos)
        pos += 8
        if pos + content_len > len(data):
            out.extend(b"TRUNCATED\n")
            return 2, bytes(out)
        content = data[pos:pos + content_len]
        pos += content_len
        out.extend(f"TS: {ts} | ID: {doc_id} | CHK: {sum(content) % 256} | TXT: ".encode())
        out.extend(content)
        out.extend(b"\n")
    return 0, bytes(out)


def run_case(agent_bin, data):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(data)
        path = tmp.name
    try:
        result = subprocess.run([agent_bin, path], capture_output=True, timeout=5)
        code, stdout = expected(data)
        assert result.returncode == code
        assert result.stdout == stdout
    finally:
        os.remove(path)


def test_tdoc_parser_behavior():
    source = "/home/user/tdoc_parser.cpp"
    agent_bin = "/home/user/tdoc_parser"
    assert os.path.isfile(source), f"Agent source missing: {source}"
    assert os.path.isfile(agent_bin), f"Agent binary missing: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"

    cases = [
        b"", b"T", b"TDOC", b"TDOC\x01", b"TDOC\x01\x00", b"XXXX\x01\x00\x00",
        b"TDOC\x02\x00\x00", b"TDOC\x01\x00\x00",
        b"TDOC\x01\x01\x00",
        b"TDOC\x01\x01\x00" + struct.pack("<IHH", 5, 7, 0),
        b"TDOC\x01\x02\x00" + struct.pack("<IHH", 5, 7, 3) + b"abc" + struct.pack("<IHH", 0xffffffff, 65535, 4) + bytes([0, 127, 128, 255]),
    ]
    for data in cases:
        run_case(agent_bin, data)

    rng = random.Random(19473)
    for _ in range(300):
        records = []
        for _ in range(rng.randint(0, 12)):
            content = bytes(rng.randrange(256) for _ in range(rng.randint(0, 100)))
            records.append((rng.randrange(2**32), rng.randrange(2**16), content))
        data = bytearray(b"TDOC\x01" + struct.pack("<H", len(records)))
        for ts, doc_id, content in records:
            data.extend(struct.pack("<IHH", ts, doc_id, len(content)))
            data.extend(content)
        run_case(agent_bin, bytes(data))
        if records:
            cut = rng.randrange(7, len(data))
            run_case(agent_bin, bytes(data[:cut]))


def test_tdoc_parser_argument_and_missing_file():
    agent_bin = "/home/user/tdoc_parser"
    missing = f"/tmp/definitely_missing_{os.getpid()}.tdoc"
    result = subprocess.run([agent_bin, missing], capture_output=True, timeout=5)
    assert result.returncode == 1
    assert result.stdout == b"INVALID_HEADER\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
