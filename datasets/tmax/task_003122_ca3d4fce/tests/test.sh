#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import sqlite3
import subprocess
import tempfile
import uuid
from collections import Counter

import pytest

VALIDATE_SCRIPT = "/home/user/validate_schema.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
HISTORICAL_DIR = "/app/historical_data"
SENSOR_FEED = "/app/sensor_feed.mp4"
EXTRACTED_FRAMES = "/home/user/extracted_frames.csv"
TELEMETRY_DB = "/home/user/telemetry.db"
MAX_FRAMES_CSV = "/home/user/max_frames_per_sec.csv"
INTEGER_RE = re.compile(r"^[+-]?\d+$")


def run_validator(path):
    return subprocess.run(
        ["python3", VALIDATE_SCRIPT, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def parse_strict_csv(path):
    rows = []
    try:
        with open(path, "r", newline="") as handle:
            for row in csv.reader(handle, strict=True):
                if len(row) != 2:
                    return None
                timestamp_text, size_text = row
                if not INTEGER_RE.fullmatch(size_text):
                    return None
                timestamp = float(timestamp_text)
                size = int(size_text)
                if not math.isfinite(timestamp) or timestamp < 0 or size <= 0:
                    return None
                rows.append((timestamp, size))
    except (OSError, ValueError, csv.Error, OverflowError):
        return None
    return rows if rows else None


def ffprobe_frames():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_frames",
            "-show_entries", "frame=pkt_pts_time,pts_time,pkt_size",
            "-of", "json", SENSOR_FEED,
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    frames = json.loads(result.stdout).get("frames", [])
    expected = []
    for frame in frames:
        timestamp_text = frame.get("pkt_pts_time", frame.get("pts_time"))
        assert timestamp_text is not None, "ffprobe returned a video frame without a presentation timestamp"
        assert "pkt_size" in frame, "ffprobe returned a video frame without pkt_size"
        timestamp = float(timestamp_text)
        size = int(frame["pkt_size"])
        assert math.isfinite(timestamp) and timestamp >= 0
        assert size > 0
        expected.append((timestamp, size))
    assert expected, "ffprobe returned no video frames"
    return expected


def test_validate_schema_adversarial_corpus():
    assert os.path.isfile(VALIDATE_SCRIPT), f"Validation script not found: {VALIDATE_SCRIPT}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".csv")]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".csv")]
    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    clean_failed = [os.path.basename(path) for path in clean_files if run_validator(path) != 0]
    evil_bypassed = [os.path.basename(path) for path in evil_files if run_validator(path) == 0]
    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean failed: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail(" | ".join(errors))

    # Unpredictable files prevent validation based on the four shipped fixture names
    # or their exact contents.
    rng = random.SystemRandom()
    token = uuid.uuid4().hex
    a = rng.randint(10, 9000)
    b = rng.randint(100, 900000)
    c = rng.randint(1, 999)
    clean_text = f"0.{a:04d},{b}\n{c}.125,{b + 17}\n{c + 1}.750,{b + 31}\n"
    bad_cases = [
        f"0.{a:04d},{b}\n-0.25,{b + 1}\n",
        f"0.{a:04d},{b}\n1.25,0\n",
        f"0.{a:04d},{b}\n1.25,-{rng.randint(1, 999)}\n",
        f"0.{a:04d},{b}\n1.25,3.14\n",
        f"0.{a:04d},{b},extra_{token}\n",
        f"0.{a:04d};{b}\n",
        f"0.{a:04d},{b}\n1.25,DROP TABLE frames_{token};\n",
        f"0.{a:04d},{b}\n__import__('os').system('{token}'),12\n",
    ]

    with tempfile.TemporaryDirectory(prefix=f"schema_{token}_") as directory:
        clean_path = os.path.join(directory, f"candidate_{uuid.uuid4().hex}.csv")
        with open(clean_path, "w", newline="") as handle:
            handle.write(clean_text)
        assert run_validator(clean_path) == 0, "Validator rejected a dynamically generated clean CSV"

        for index, contents in enumerate(bad_cases):
            bad_path = os.path.join(directory, f"candidate_{uuid.uuid4().hex}_{index}.csv")
            with open(bad_path, "w", newline="") as handle:
                handle.write(contents)
            assert run_validator(bad_path) == 1, f"Validator accepted dynamic malicious case {index}"


def test_extracted_frames():
    assert os.path.isfile(EXTRACTED_FRAMES), f"Extracted frames file not found: {EXTRACTED_FRAMES}"
    with open(EXTRACTED_FRAMES, "r", newline="") as handle:
        rows = list(csv.reader(handle, strict=True))

    assert rows, "Extracted frames file is empty."
    actual = []
    for row in rows:
        assert len(row) == 2, f"Expected 2 columns, got {len(row)} in row: {row}"
        try:
            timestamp = float(row[0])
            size = int(row[1])
        except ValueError as exc:
            pytest.fail(f"Invalid data type in extracted frames: {row} - {exc}")
        assert math.isfinite(timestamp) and timestamp >= 0, f"Timestamp must be finite and non-negative: {timestamp}"
        assert size > 0, f"Size must be strictly greater than 0: {size}"
        actual.append((timestamp, size))

    expected = ffprobe_frames()
    assert len(actual) == len(expected), f"Expected {len(expected)} ffprobe frames, found {len(actual)} CSV rows"
    for index, ((actual_ts, actual_size), (expected_ts, expected_size)) in enumerate(zip(actual, expected)):
        assert math.isclose(actual_ts, expected_ts, rel_tol=0, abs_tol=1e-6), (
            f"Frame {index} timestamp differs from ffprobe: {actual_ts} != {expected_ts}"
        )
        assert actual_size == expected_size, (
            f"Frame {index} size differs from ffprobe: {actual_size} != {expected_size}"
        )


def expected_ingested_rows():
    rows = []
    for name in sorted(os.listdir(HISTORICAL_DIR)):
        if not name.endswith(".csv"):
            continue
        parsed = parse_strict_csv(os.path.join(HISTORICAL_DIR, name))
        if parsed is not None:
            rows.extend(parsed)
    extracted = parse_strict_csv(EXTRACTED_FRAMES)
    assert extracted is not None, "Extracted telemetry is not a clean schema-conforming CSV"
    rows.extend(extracted)
    return rows


def test_telemetry_db():
    assert os.path.isfile(TELEMETRY_DB), f"Database not found: {TELEMETRY_DB}"
    conn = sqlite3.connect(TELEMETRY_DB)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='frames';")
        assert cursor.fetchone() is not None, "Table 'frames' not found in database."

        columns = cursor.execute("PRAGMA table_info(frames)").fetchall()
        assert [(column[1], column[2].upper()) for column in columns] == [
            ("timestamp", "REAL"), ("size", "INTEGER")
        ], f"Incorrect frames schema: {columns}"

        indexes = cursor.execute(
            "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='frames';"
        ).fetchall()
        assert indexes, "No index found on the 'frames' table."
        assert any("timestamp" in (sql or "").lower() for _, sql in indexes), (
            "No frames index references timestamp for time-window access"
        )

        db_rows = cursor.execute(
            "SELECT timestamp, size, typeof(timestamp), typeof(size) FROM frames"
        ).fetchall()
        assert all(row[2] == "real" and row[3] == "integer" for row in db_rows), (
            "frames contains values stored with incorrect SQLite types"
        )
        actual = Counter((float(row[0]), int(row[1])) for row in db_rows)
        expected = Counter(expected_ingested_rows())
        assert actual == expected, "frames does not contain exactly all and only rows from clean input files"
    finally:
        conn.close()


def test_max_frames_per_sec():
    assert os.path.isfile(MAX_FRAMES_CSV), f"Result CSV not found: {MAX_FRAMES_CSV}"
    with open(MAX_FRAMES_CSV, "r", newline="") as handle:
        reader = csv.reader(handle, strict=True)
        headers = next(reader, None)
        assert headers == ["window_start", "max_size"], f"Incorrect headers: {headers}"
        rows = list(reader)

    assert rows, "Result CSV is empty (excluding headers)."
    actual = {}
    for row in rows:
        assert len(row) == 2, f"Expected 2 columns, got {len(row)} in row: {row}"
        try:
            window_start = float(row[0])
            max_size = int(row[1])
        except ValueError as exc:
            pytest.fail(f"Invalid data type in result CSV: {row} - {exc}")
        assert math.isfinite(window_start) and window_start >= 0, f"Invalid window start: {window_start}"
        assert max_size > 0, f"Max size must be strictly greater than 0: {max_size}"
        assert window_start == math.floor(window_start), f"Window start is not a 1-second boundary: {window_start}"
        assert window_start not in actual, f"Duplicate result for window {window_start}"
        actual[window_start] = max_size

    expected = {}
    for timestamp, size in expected_ingested_rows():
        window = float(math.floor(timestamp))
        expected[window] = max(size, expected.get(window, 0))
    assert actual == expected, f"Incorrect per-window maxima: expected {expected}, got {actual}"
TEST_EOF

reward=0
if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
