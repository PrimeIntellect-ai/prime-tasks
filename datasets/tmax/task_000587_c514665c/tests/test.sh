#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import subprocess
import json
import csv
import math
import secrets
import cv2


def get_sanitizer():
    candidates = glob.glob("/home/user/sanitizer*")
    for c in candidates:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def run_sanitizer(sanitizer, data):
    return subprocess.run(
        [sanitizer], input=data, capture_output=True, timeout=15, check=False
    )


def parse_jsonl(data):
    text = data.decode("utf-8")
    assert text.strip(), "Sanitizer emitted empty output"
    records = []
    for line in text.splitlines():
        if line.strip():
            records.append(json.loads(line))
    assert records, "Sanitizer emitted no JSON records"
    return records


def assert_valid_unicode(value):
    if isinstance(value, str):
        value.encode("utf-8")
    elif isinstance(value, list):
        for item in value:
            assert_valid_unicode(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            assert_valid_unicode(key)
            assert_valid_unicode(item)


def test_video_telemetry():
    csv_path = "/home/user/video_telemetry.csv"
    video_path = "/app/telemetry_dashboard.mp4"
    assert os.path.isfile(csv_path), f"Missing CSV at {csv_path}"
    assert os.path.isfile(video_path), f"Missing source video at {video_path}"

    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert "frame_index" in reader.fieldnames, "Missing frame_index column"
    assert "red_intensity" in reader.fieldnames, "Missing red_intensity column"
    assert len(rows) == 300, f"Expected 300 rows, got {len(rows)}"

    # Retain the original alternating-pattern assertions.
    val0 = float(rows[0]["red_intensity"])
    start_val = 0.0 if val0 < 0.5 else 1.0
    for i, row in enumerate(rows):
        block = i // 10
        expected_val = start_val if block % 2 == 0 else (1.0 - start_val)
        val = float(row["red_intensity"])
        assert abs(val - expected_val) < 0.1, f"Frame {i} expected {expected_val}, got {val}"

    # Independently extract and normalize the actual red-channel time series.
    cap = cv2.VideoCapture(video_path)
    actual = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        actual.append(float(frame[0:50, 0:50, 2].mean()))
    cap.release()

    assert len(actual) == 300, f"Expected 300 video frames, got {len(actual)}"
    lo, hi = min(actual), max(actual)
    assert hi > lo, "Source video has no red-channel variation"
    expected = [(value - lo) / (hi - lo) for value in actual]

    for i, (row, expected_value) in enumerate(zip(rows, expected)):
        try:
            frame_index = int(row["frame_index"])
            value = float(row["red_intensity"])
        except (TypeError, ValueError) as exc:
            raise AssertionError(f"Invalid CSV values on row {i}: {row}") from exc
        assert frame_index == i, f"Row {i} has frame_index {frame_index}"
        assert math.isfinite(value), f"Frame {i} has non-finite intensity"
        assert 0.0 <= value <= 1.0, f"Frame {i} is not normalized: {value}"
        assert abs(value - expected_value) < 0.02, (
            f"Frame {i} expected extracted intensity {expected_value}, got {value}"
        )


def test_sanitizer_clean_corpus():
    sanitizer = get_sanitizer()
    assert sanitizer is not None, "Sanitizer script not found or not executable in /home/user/"

    clean_dir = "/app/clean_corpus"
    assert os.path.isdir(clean_dir), f"Clean corpus dir missing: {clean_dir}"
    files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert files, "Clean corpus is empty"

    failed = []
    for f in files:
        path = os.path.join(clean_dir, f)
        with open(path, "rb") as infile:
            original = infile.read()
        proc = run_sanitizer(sanitizer, original)
        if proc.returncode != 0 or proc.stdout != original:
            failed.append(f)
    assert not failed, f"{len(failed)} of {len(files)} clean modified: {failed}"

    # An unpredictable valid corpus must also be preserved byte-for-byte.
    base = secrets.randbelow(800000) + 100000
    nonce = secrets.token_hex(12)
    generated = (
        json.dumps({"timestamp": base, "value": -17.25, "tag": nonce}, separators=(",", ":")) + "\n" +
        json.dumps({"timestamp": base + 17, "value": 0, "nested": {"ok": True, "items": [1, 2, nonce]}}, separators=(",", ":")) + "\n" +
        json.dumps({"timestamp": base + 41, "value": 999999, "text": "valid unicode Ω"}, separators=(",", ":")) + "\n"
    ).encode("utf-8")
    proc = run_sanitizer(sanitizer, generated)
    assert proc.returncode == 0, f"Sanitizer crashed on generated clean input: {proc.stderr!r}"
    assert proc.stdout == generated, "Generated clean JSON-lines were not preserved exactly"


def test_sanitizer_evil_corpus():
    sanitizer = get_sanitizer()
    assert sanitizer is not None, "Sanitizer script not found or not executable in /home/user/"

    evil_dir = "/app/evil_corpus"
    assert os.path.isdir(evil_dir), f"Evil corpus dir missing: {evil_dir}"
    files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert files, "Evil corpus is empty"

    failed = []
    for f in files:
        path = os.path.join(evil_dir, f)
        with open(path, "rb") as infile:
            evil_data = infile.read()
        proc = run_sanitizer(sanitizer, evil_data)
        if proc.returncode != 0:
            failed.append(f"{f} (crashed)")
            continue
        try:
            records = parse_jsonl(proc.stdout)
            for record in records:
                assert_valid_unicode(record)
            assert [r.get("timestamp") for r in records] == [1000, 1020]
            assert records[0] == {"timestamp": 1000, "value": 42}
            assert records[1].get("value") == 43
            assert "bad_unicode" in records[1]
            assert isinstance(records[1]["bad_unicode"], str)
        except Exception:
            failed.append(f"{f} (invalid or incorrectly sanitized json)")
    assert not failed, f"{len(failed)} of {len(files)} evil bypassed: {failed}"

    # Exercise deduplication, bounce filtering, and malformed Unicode with
    # values unavailable before verification.
    base = secrets.randbelow(700000) + 200000
    nonce = secrets.token_hex(16)
    first = {"timestamp": base, "value": 42, "nonce": nonce}
    bounce = {"timestamp": base + 4, "value": 10**12, "nonce": "bounce-" + nonce}
    after = {"timestamp": base + 50, "value": -999999, "nonce": "after-" + nonce}

    first_line = json.dumps(first, separators=(",", ":"))
    bounce_line = json.dumps(bounce, separators=(",", ":"))
    after_line = json.dumps(after, separators=(",", ":"))
    malformed_line = (
        '{"timestamp":%d,"value":73,"nonce":"%s",'
        '"bad_unicode":"prefix\\uD83D\\uDE0suffix",'
        '"nested":{"preserve":[1,true,"%s"]}}'
    ) % (base + 25, nonce, nonce)
    bounce_after_malformed = json.dumps(
        {"timestamp": base + 31, "value": 10**15, "nonce": "second-bounce-" + nonce},
        separators=(",", ":")
    )
    evil = ("\n".join([
        first_line,
        first_line,
        bounce_line,
        malformed_line,
        bounce_after_malformed,
        after_line,
        after_line,
    ]) + "\n").encode("utf-8")

    proc = run_sanitizer(sanitizer, evil)
    assert proc.returncode == 0, f"Sanitizer crashed on generated evil input: {proc.stderr!r}"
    records = parse_jsonl(proc.stdout)
    for record in records:
        assert isinstance(record, dict), "Each output line must be a JSON object"
        assert_valid_unicode(record)

    assert [record.get("timestamp") for record in records] == [base, base + 25, base + 50], (
        "Exact duplicates and records within 10ms of the previous valid record were not removed correctly"
    )
    assert records[0] == first
    assert records[2] == after
    repaired = records[1]
    assert repaired.get("value") == 73
    assert repaired.get("nonce") == nonce
    assert repaired.get("nested") == {"preserve": [1, True, nonce]}
    assert "bad_unicode" in repaired and isinstance(repaired["bad_unicode"], str)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
