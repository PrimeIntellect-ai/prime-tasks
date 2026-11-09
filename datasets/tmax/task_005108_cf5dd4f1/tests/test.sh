#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import gzip
import os
import subprocess

import pytest

CHUNKS_DIR = "/home/user/chunks"
FRAME_SIZE = 320 * 240
FRAMES_PER_CHUNK = 30


def decode_reference_video():
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", "/app/video.mp4",
            "-vf", "fps=10", "-pix_fmt", "gray",
            "-f", "rawvideo", "pipe:1",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    assert len(result.stdout) > 0, "ffmpeg decoded no frames from /app/video.mp4"
    assert len(result.stdout) % FRAME_SIZE == 0, "Decoded stream is not composed of 320x240 grayscale frames"
    return result.stdout


def expected_chunk_data():
    raw = decode_reference_video()
    chunk_size = FRAMES_PER_CHUNK * FRAME_SIZE
    return [raw[offset:offset + chunk_size] for offset in range(0, len(raw), chunk_size)]


def parse_csv_text(text):
    text = text.lstrip("\ufeff")
    return list(csv.reader(text.splitlines()))


def test_utf16_csv_exists_and_valid():
    csv_path = "/home/user/chunks/index_utf16.csv"
    assert os.path.exists(csv_path), f"Expected file {csv_path} does not exist."

    try:
        with open(csv_path, "rb") as f:
            content = f.read()
            text = content.decode("utf-16le")
    except Exception as e:
        pytest.fail(f"Failed to decode {csv_path} as UTF-16LE: {e}")

    assert "chunk_name,num_frames,compressed_bytes" in text, "CSV header is missing or incorrect."


def test_chunks_exist_and_valid_gzip():
    chunks = glob.glob(os.path.join(CHUNKS_DIR, "chunk_*.gz"))
    assert chunks, f"No chunk files found in {CHUNKS_DIR}."

    for chunk in chunks:
        try:
            with gzip.open(chunk, "rb") as f:
                f.read()
        except Exception as e:
            pytest.fail(f"Chunk {chunk} is not a valid gzip file: {e}")


def test_latest_symlink_exists():
    symlink_path = os.path.join(CHUNKS_DIR, "latest.gz")
    assert os.path.islink(symlink_path), f"Expected symlink at {symlink_path} is missing or not a symlink."


def test_compression_metric_threshold():
    chunks = glob.glob(os.path.join(CHUNKS_DIR, "chunk_*.gz"))
    assert chunks, f"No chunk files found in {CHUNKS_DIR}."

    total_size = sum(os.path.getsize(chunk) for chunk in chunks)
    threshold = 1500000

    assert total_size <= threshold, f"Total compressed size {total_size} bytes exceeds the threshold of {threshold} bytes. Ensure max compression (level 9) is used."


def test_chunks_are_exact_decoded_frames_with_exact_rotation():
    expected = expected_chunk_data()
    expected_names = [f"chunk_{i:03d}.gz" for i in range(len(expected))]
    actual_paths = sorted(glob.glob(os.path.join(CHUNKS_DIR, "chunk_*.gz")))
    actual_names = [os.path.basename(path) for path in actual_paths]

    assert actual_names == expected_names, f"Expected chunk files {expected_names}, found {actual_names}"

    for index, (path, expected_bytes) in enumerate(zip(actual_paths, expected)):
        assert os.path.isfile(path) and not os.path.islink(path), f"{path} must be a regular gzip chunk file"
        with gzip.open(path, "rb") as f:
            actual_bytes = f.read()
        expected_frames = len(expected_bytes) // FRAME_SIZE
        assert actual_bytes == expected_bytes, f"{path} does not contain the expected decoded grayscale frames"
        assert len(actual_bytes) == expected_frames * FRAME_SIZE
        if index < len(expected) - 1:
            assert expected_frames == FRAMES_PER_CHUNK, f"{path} was not rotated after exactly 30 frames"
        else:
            assert 1 <= expected_frames <= FRAMES_PER_CHUNK


def test_latest_symlink_points_to_most_recent_chunk():
    expected = expected_chunk_data()
    latest_chunk = os.path.join(CHUNKS_DIR, f"chunk_{len(expected) - 1:03d}.gz")
    symlink_path = os.path.join(CHUNKS_DIR, "latest.gz")

    assert os.path.islink(symlink_path)
    assert os.path.exists(symlink_path), "latest.gz is a dangling symlink"
    assert os.path.realpath(symlink_path) == os.path.realpath(latest_chunk), "latest.gz does not point to the most recently completed chunk"


def test_csv_rows_match_chunks_frames_and_compressed_sizes():
    expected_data = expected_chunk_data()
    expected_rows = [["chunk_name", "num_frames", "compressed_bytes"]]
    for index, data in enumerate(expected_data):
        name = f"chunk_{index:03d}.gz"
        path = os.path.join(CHUNKS_DIR, name)
        expected_rows.append([name, str(len(data) // FRAME_SIZE), str(os.path.getsize(path))])

    utf8_path = os.path.join(CHUNKS_DIR, "index.csv")
    assert os.path.isfile(utf8_path), f"Expected file {utf8_path} does not exist."
    with open(utf8_path, "rb") as f:
        utf8_bytes = f.read()
    try:
        utf8_text = utf8_bytes.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"{utf8_path} is not valid UTF-8: {e}")

    utf16_path = os.path.join(CHUNKS_DIR, "index_utf16.csv")
    with open(utf16_path, "rb") as f:
        utf16_text = f.read().decode("utf-16le")

    assert parse_csv_text(utf8_text) == expected_rows, "index.csv does not accurately describe the chunk files"
    assert parse_csv_text(utf16_text) == expected_rows, "index_utf16.csv does not accurately describe the chunk files"
    assert utf16_text.lstrip("\ufeff") == utf8_text.lstrip("\ufeff"), "index_utf16.csv is not the UTF-16LE conversion of index.csv"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
