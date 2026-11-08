#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import struct
import subprocess
import tempfile
import zlib


def test_video_frames_csv():
    csv_path = "/home/user/video_frames.csv"
    assert os.path.exists(csv_path), f"Missing {csv_path}"

    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "packet=pts_time,size", "-of", "csv=p=0",
        "/app/experiment_video.mp4"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)

    expected_rows = []
    for i, line in enumerate(result.stdout.strip().split('\n')):
        if not line:
            continue
        parts = line.split(',')
        if len(parts) >= 2:
            expected_rows.append((str(i), parts[1].strip()))

    actual_rows = []
    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            if row[0] == "frame_index":
                continue
            actual_rows.append((row[0].strip(), row[1].strip()))

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(actual_rows)}"
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch: expected {expected}, got {actual}"


def test_wal_filter_executable():
    executable = "/home/user/wal_filter"
    assert os.path.exists(executable), f"Missing executable {executable}"
    assert os.path.isfile(executable), f"{executable} is not a regular file"
    assert os.access(executable, os.X_OK), f"File {executable} is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wal_filter must be a compiled executable"


def test_wal_filter_adversarial_corpus():
    executable = "/home/user/wal_filter"
    clean_dir = "/test_corpus/clean/"
    evil_dir = "/test_corpus/evil/"

    assert os.path.exists(clean_dir), f"Missing clean corpus dir {clean_dir}"
    assert os.path.exists(evil_dir), f"Missing evil corpus dir {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        res = subprocess.run([executable, cf], capture_output=True, text=True)
        out = res.stdout.strip()
        if res.returncode != 0 or out != "CLEAN":
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        res = subprocess.run([executable, ef], capture_output=True, text=True)
        out = res.stdout.strip()
        if res.returncode == 0 and out != "EVIL":
            evil_failures.append(os.path.basename(ef))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    assert not error_msgs, " ; ".join(error_msgs)


def make_wal(metadata, payload):
    metadata_bytes = json.dumps(metadata, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return b"WAL\x00" + struct.pack("<I", len(metadata_bytes)) + metadata_bytes + zlib.compress(payload)


def run_and_require(executable, path, expected):
    result = subprocess.run([executable, path], capture_output=True, timeout=5)
    assert result.returncode == 0, f"{executable} returned {result.returncode} for {os.path.basename(path)}"
    allowed = {expected.encode(), expected.encode() + b"\n"}
    assert result.stdout in allowed, (
        f"Expected exactly {expected} for {os.path.basename(path)}, got {result.stdout!r}"
    )


def test_source_and_generated_wal_cases():
    source = "/home/user/wal_filter.c"
    assert os.path.exists(source), f"Missing {source}"
    assert os.path.isfile(source), f"{source} is not a regular file"
    assert not os.path.islink(source), f"{source} must be an actual source file"
    assert os.path.getsize(source) > 0, f"{source} is empty"

    with tempfile.TemporaryDirectory(prefix="wal_verify_") as td:
        rebuilt = os.path.join(td, "rebuilt_" + secrets.token_hex(8))
        compile_result = subprocess.run(
            ["gcc", source, "-o", rebuilt, "-ljson-c", "-lz"],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, f"wal_filter.c did not compile: {compile_result.stderr}"

        clean_blobs = [
            make_wal({"checksum": secrets.token_hex(12)}, os.urandom(257)),
            make_wal({"kind": "telemetry", "checksum": 0, "nested": {"ok": True}}, os.urandom(3)),
            make_wal({"checksum": "unicode-✓", "samples": [1, 2, 3]}, b""),
        ]

        good_json = json.dumps({"checksum": secrets.token_hex(6)}, separators=(",", ":")).encode()
        compressed = zlib.compress(os.urandom(128))
        evil_blobs = [
            b"BAD\x00" + struct.pack("<I", len(good_json)) + good_json + compressed,
            b"WAL\x00\x01\x02",
            b"WAL\x00" + struct.pack("<I", len(good_json) + 500) + good_json,
            b"WAL\x00" + struct.pack("<I", 15) + b'{"checksum": ]' + compressed,
            make_wal({"note": "the word checksum is not a field"}, os.urandom(32)),
            b"WAL\x00" + struct.pack("<I", len(good_json)) + good_json + b"not-a-zlib-stream",
            b"WAL\x00" + struct.pack("<I", len(good_json)) + good_json + compressed[:-3],
        ]

        cases = []
        for expected, blobs in (("CLEAN", clean_blobs), ("EVIL", evil_blobs)):
            for blob in blobs:
                path = os.path.join(td, secrets.token_hex(14) + ".wal")
                with open(path, "wb") as f:
                    f.write(blob)
                cases.append((path, expected))

        for executable in ("/home/user/wal_filter", rebuilt):
            for path, expected in cases:
                run_and_require(executable, path, expected)


def independently_classify(path):
    try:
        data = open(path, "rb").read()
        if len(data) < 8 or data[:4] != b"WAL\x00":
            return "EVIL"
        metadata_len = struct.unpack("<I", data[4:8])[0]
        end = 8 + metadata_len
        if end > len(data):
            return "EVIL"
        metadata = json.loads(data[8:end].decode("utf-8"))
        if not isinstance(metadata, dict) or "checksum" not in metadata:
            return "EVIL"
        compressed = data[end:]
        if not compressed:
            return "EVIL"
        decoder = zlib.decompressobj()
        decoder.decompress(compressed)
        decoder.flush()
        if not decoder.eof or decoder.unused_data:
            return "EVIL"
        return "CLEAN"
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, zlib.error, struct.error):
        return "EVIL"


def test_dataset_classification_log():
    log_path = "/home/user/dataset_classification.log"
    assert os.path.exists(log_path), f"Missing {log_path}"
    assert os.path.isfile(log_path), f"{log_path} is not a regular file"

    dataset_files = sorted(
        name for name in os.listdir("/dataset")
        if os.path.isfile(os.path.join("/dataset", name))
    )
    expected = {
        name: independently_classify(os.path.join("/dataset", name))
        for name in dataset_files
    }

    with open(log_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == len(dataset_files), "Classification log must contain exactly one line per dataset file"
    actual = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid classification line: {line!r}"
        name, verdict = parts
        assert name not in actual, f"Duplicate classification for {name}"
        assert verdict in ("CLEAN", "EVIL"), f"Invalid verdict for {name}: {verdict}"
        actual[name] = verdict

    assert actual == expected, f"Classification log mismatch: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
