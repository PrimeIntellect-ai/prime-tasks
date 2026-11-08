#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import secrets
import subprocess
import tempfile
import pytest

FILTER = "/home/user/filter.go"
EXTRACTED = "/home/user/extracted.csv"
CLEAN_EXTRACTED = "/home/user/clean_extracted.csv"
VIDEO = "/app/video/feed.mp4"


def run_filter(input_path, output_path):
    return subprocess.run(
        ["go", "run", FILTER, input_path, output_path],
        capture_output=True,
        text=True,
    )


def test_clean_extracted_csv():
    """Verify that the clean_extracted.csv file exists and contains valid data."""
    file_path = CLEAN_EXTRACTED
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, f"{file_path} is empty."

    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid CSV format in {file_path}: expected 2 columns, got {len(parts)} in line '{line}'"
        try:
            ts = float(parts[0])
            size = float(parts[1])
        except ValueError:
            pytest.fail(f"Values in {file_path} are not valid floats: {line}")

        assert size >= 0, f"Negative size found in {file_path}: {line}"


def test_go_filter_clean_corpus():
    """Verify that the Go filter accepts all clean corpus files."""
    filter_script = FILTER
    assert os.path.isfile(filter_script), f"Go filter script missing: {filter_script}"

    clean_files = glob.glob("/app/corpus/clean/*.csv")
    assert len(clean_files) > 0, "No clean corpus files found in /app/corpus/clean/"

    failed_files = []
    for f in clean_files:
        with tempfile.NamedTemporaryFile(suffix=".csv") as tmp:
            res = subprocess.run(
                ["go", "run", filter_script, f, tmp.name],
                capture_output=True,
                text=True
            )
            if res.returncode != 0:
                failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified or rejected: {failed_files}"


def test_go_filter_evil_corpus():
    """Verify that the Go filter rejects all evil corpus files."""
    filter_script = FILTER
    assert os.path.isfile(filter_script), f"Go filter script missing: {filter_script}"

    evil_files = glob.glob("/app/corpus/evil/*.csv")
    assert len(evil_files) > 0, "No evil corpus files found in /app/corpus/evil/"

    failed_files = []
    for f in evil_files:
        with tempfile.NamedTemporaryFile(suffix=".csv") as tmp:
            res = subprocess.run(
                ["go", "run", filter_script, f, tmp.name],
                capture_output=True,
                text=True
            )
            if res.returncode == 0:
                failed_files.append(os.path.basename(f))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {failed_files}"


def expected_video_frames():
    res = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_frames",
            "-show_entries", "frame=pkt_pts_time,pts_time,pkt_size",
            "-of", "json", VIDEO,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    frames = json.loads(res.stdout).get("frames", [])
    expected = []
    for frame in frames:
        timestamp = frame.get("pkt_pts_time", frame.get("pts_time"))
        assert timestamp is not None, "ffprobe returned a video frame without a presentation timestamp"
        assert "pkt_size" in frame, "ffprobe returned a video frame without a packet size"
        expected.append((float(timestamp), float(frame["pkt_size"])))
    assert expected, "ffprobe found no video frames"
    return expected


def read_strict_two_column_csv(path):
    with open(path, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"{path} is empty"
    parsed = []
    for row in rows:
        assert len(row) == 2, f"Expected exactly two columns in {path}, got {row!r}"
        try:
            timestamp = float(row[0])
            size = float(row[1])
        except ValueError as exc:
            pytest.fail(f"Unparseable row in {path}: {row!r}: {exc}")
        assert math.isfinite(timestamp), f"Non-finite timestamp in {path}: {row!r}"
        assert math.isfinite(size), f"Non-finite size in {path}: {row!r}"
        assert size >= 0, f"Negative size in {path}: {row!r}"
        parsed.append((timestamp, size))
    return parsed


def test_extracted_csv_matches_frames_recomputed_from_video():
    assert os.path.isfile(EXTRACTED), f"{EXTRACTED} is missing"
    actual = read_strict_two_column_csv(EXTRACTED)
    expected = expected_video_frames()
    assert actual == expected, "extracted.csv does not contain every frame timestamp and packet size from feed.mp4"


def test_integration_output_is_exact_filter_copy():
    assert os.path.isfile(CLEAN_EXTRACTED), f"{CLEAN_EXTRACTED} is missing"
    with open(EXTRACTED, "rb") as f:
        extracted_bytes = f.read()
    with open(CLEAN_EXTRACTED, "rb") as f:
        clean_bytes = f.read()
    assert clean_bytes == extracted_bytes, "clean_extracted.csv does not preserve extracted.csv exactly"

    with tempfile.TemporaryDirectory() as td:
        fresh_output = os.path.join(td, secrets.token_hex(12) + ".csv")
        res = run_filter(EXTRACTED, fresh_output)
        assert res.returncode == 0, f"filter.go rejected its generated extracted.csv: {res.stderr}"
        with open(fresh_output, "rb") as f:
            assert f.read() == extracted_bytes, "filter.go did not preserve extracted.csv rows exactly"


def test_clean_corpus_outputs_are_preserved_exactly():
    for input_path in glob.glob("/app/corpus/clean/*.csv"):
        with tempfile.TemporaryDirectory() as td:
            output_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            res = run_filter(input_path, output_path)
            assert res.returncode == 0, f"filter.go rejected {input_path}: {res.stderr}"
            with open(input_path, "rb") as src, open(output_path, "rb") as dst:
                assert dst.read() == src.read(), f"filter.go did not preserve rows from {input_path}"


def test_filter_on_unseen_random_clean_and_adversarial_inputs():
    nonce = secrets.randbelow(900000000) + 100000000
    valid = (
        f"0.{nonce},1\n"
        f"-{nonce}.25,0\n"
        f"1.25e-3,{nonce}.5\n"
        f"6.022e23,9.109e-31\n"
    ).encode()

    bad_inputs = [
        b"NaN,1\n",
        b"+Inf,1\n",
        b"-Inf,1\n",
        b"1,NaN\n",
        b"1,+Inf\n",
        b"1,-Inf\n",
        b"1,-0.000001\n",
        b"1e999,2\n",
        b"1,2e999\n",
        b"not-a-number,2\n",
        b"1,not-a-number\n",
        b"1\n",
        b"1,2,3\n",
        b"\"unterminated,2\n",
    ]

    with tempfile.TemporaryDirectory() as td:
        valid_in = os.path.join(td, secrets.token_hex(16) + ".csv")
        valid_out = os.path.join(td, secrets.token_hex(16) + ".csv")
        with open(valid_in, "wb") as f:
            f.write(valid)
        res = run_filter(valid_in, valid_out)
        assert res.returncode == 0, f"filter.go rejected unseen valid data: {res.stderr}"
        with open(valid_out, "rb") as f:
            assert f.read() == valid, "filter.go did not write the exact same unseen valid rows"

        for index, payload in enumerate(bad_inputs):
            bad_in = os.path.join(td, f"{secrets.token_hex(16)}-{index}.csv")
            bad_out = os.path.join(td, f"{secrets.token_hex(16)}-{index}.out.csv")
            with open(bad_in, "wb") as f:
                f.write(payload)
            res = run_filter(bad_in, bad_out)
            assert res.returncode == 1, f"filter.go did not exit 1 for adversarial input {payload!r}; stderr={res.stderr!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
