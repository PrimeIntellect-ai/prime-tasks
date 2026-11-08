#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_archiver.py
import collections
import csv
import ctypes
import glob
import json
import os
import shutil
import struct
import subprocess
import uuid

LOG_DIR = "/home/user/logs"
ARCHIVE_DIR = "/home/user/archive"
PROJECT_DIR = "/home/user/archiver"


def expected_from_logs():
    expected = []
    for root, _, files in os.walk(LOG_DIR):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".jsonl"):
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        if not line.strip():
                            continue
                        data = json.loads(line)
                        if data.get("level") == "CRITICAL":
                            expected.append({"source": name, "data": data})
            elif name.endswith(".csv"):
                with open(path, "r", encoding="utf-8", newline="") as f:
                    for data in csv.DictReader(f):
                        if data.get("status") == "ERROR":
                            expected.append({"source": name, "data": data})
    return expected


def canonical_counter(records):
    return collections.Counter(
        json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        for record in records
    )


def validate_archive(expected, require_original_counts=False):
    assert os.path.isdir(ARCHIVE_DIR), f"Directory {ARCHIVE_DIR} does not exist."

    temp_files = glob.glob(os.path.join(ARCHIVE_DIR, "*.tmp"))
    assert not temp_files, f"Found temporary files in archive directory, which violates atomic write requirements: {temp_files}"

    archive_files = sorted(glob.glob(os.path.join(ARCHIVE_DIR, "archive_part_*.jsonl")))
    assert archive_files, "No archive_part_*.jsonl files found in the archive directory."

    expected_names = [
        os.path.join(ARCHIVE_DIR, f"archive_part_{i:03d}.jsonl")
        for i in range(1, (len(expected) + 9) // 10 + 1)
    ]
    assert archive_files == expected_names, f"Incorrect archive chunk names: {archive_files}"

    actual = []
    sources_found = set()
    app_jsonl_count = 0
    web_csv_count = 0

    for index, file_path in enumerate(archive_files):
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()

        if index == len(archive_files) - 1:
            assert len(lines) <= 10, f"File {file_path} exceeds the 10 records per chunk limit."
        else:
            assert len(lines) == 10, f"File {file_path} is not the last chunk but does not contain exactly 10 records."

        expected_size = min(10, len(expected) - index * 10)
        assert len(lines) == expected_size, f"Incorrect record count in {file_path}."

        for line in lines:
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise AssertionError(f"Invalid JSON line in {file_path}: {line}") from exc
            assert isinstance(record, dict), f"Archive line is not a JSON object: {record}"
            assert "source" in record, f"Missing 'source' key in record: {record}"
            assert "data" in record, f"Missing 'data' key in record: {record}"
            assert isinstance(record["data"], dict), f"'data' is not an object: {record}"

            source = record["source"]
            data = record["data"]
            sources_found.add(source)
            if require_original_counts:
                if source == "app.jsonl":
                    assert data.get("level") == "CRITICAL", f"Expected only CRITICAL level for app.jsonl, got: {data}"
                    app_jsonl_count += 1
                elif source == "web.csv":
                    assert data.get("status") == "ERROR", f"Expected only ERROR status for web.csv, got: {data}"
                    web_csv_count += 1
                else:
                    raise AssertionError(f"Unexpected source file in archive: {source}")
            actual.append(record)

    assert canonical_counter(actual) == canonical_counter(expected), \
        "Archived records do not exactly match the qualifying input records."

    if require_original_counts:
        assert len(actual) == 10, f"Expected exactly 10 extracted records, found {len(actual)}."
        assert app_jsonl_count == 6, f"Expected 6 records from app.jsonl, found {app_jsonl_count}."
        assert web_csv_count == 4, f"Expected 4 records from web.csv, found {web_csv_count}."
        assert "app.jsonl" in sources_found, "Missing records from app.jsonl."
        assert "web.csv" in sources_found, "Missing records from web.csv."
        expected_file = os.path.join(ARCHIVE_DIR, "archive_part_001.jsonl")
        assert os.path.isfile(expected_file), f"Expected file {expected_file} was not found. Check chunk naming logic."


def build_binary():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(manifest), "Missing /home/user/archiver/Cargo.toml"
    assert os.path.isfile(main_rs), "Missing Rust application source at /home/user/archiver/src/main.rs"

    subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", manifest],
        cwd=PROJECT_DIR, check=True, timeout=240
    )
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=PROJECT_DIR, text=True, timeout=60
    ))
    root_manifest = os.path.realpath(manifest)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == root_manifest]
    assert len(packages) == 1, "Could not identify the archiver Cargo package."
    bins = [t for t in packages[0]["targets"] if "bin" in t["kind"]]
    main_bins = [t for t in bins if os.path.realpath(t["src_path"]) == os.path.realpath(main_rs)]
    if main_bins:
        target = main_bins[0]
    else:
        assert len(bins) == 1, "The Cargo project must provide an unambiguous executable."
        target = bins[0]
    binary = os.path.join(metadata["target_directory"], "release", target["name"])
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), f"Release executable was not built: {binary}"
    return binary


def install_challenge_logs():
    shutil.rmtree(LOG_DIR)
    os.makedirs(os.path.join(LOG_DIR, "deep", "json"), exist_ok=True)
    os.makedirs(os.path.join(LOG_DIR, "other", "deeper", "csv"), exist_ok=True)
    token = uuid.uuid4().hex

    json_path = os.path.join(LOG_DIR, "deep", "json", "challenge_app.jsonl")
    json_records = []
    for i in range(12):
        json_records.append({
            "id": f"json-{i}-{token}", "level": "CRITICAL",
            "message": f"critical message {i}", "nested": {"value": i, "token": token}
        })
    json_records.extend([
        {"id": "lower-" + token, "level": "critical", "message": "must not match"},
        {"id": "space-" + token, "level": "CRITICAL ", "message": "must not match"},
        {"id": "info-" + token, "level": "INFO", "message": "must not match"},
    ])
    with open(json_path, "w", encoding="utf-8") as f:
        for record in json_records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    csv_path = os.path.join(LOG_DIR, "other", "deeper", "csv", "challenge_web.csv")
    csv_rows = []
    for i in range(11):
        csv_rows.append({
            "request_id": f"csv-{i}-{token}", "status": "ERROR",
            "endpoint": f"/challenge/{i}", "note": f"quoted, value {i}"
        })
    csv_rows.extend([
        {"request_id": "ok-" + token, "status": "OK", "endpoint": "/ignore", "note": "ignored"},
        {"request_id": "lower-" + token, "status": "error", "endpoint": "/ignore2", "note": "ignored"},
    ])
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["request_id", "status", "endpoint", "note"])
        writer.writeheader()
        writer.writerows(csv_rows)

    return expected_from_logs()


def clear_archive():
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    for name in os.listdir(ARCHIVE_DIR):
        path = os.path.join(ARCHIVE_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def run_with_atomic_write_watch(binary):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    mask = IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed with errno {ctypes.get_errno()}"
    try:
        wd = libc.inotify_add_watch(fd, ARCHIVE_DIR.encode(), mask)
        assert wd >= 0, f"Could not watch archive directory, errno {ctypes.get_errno()}"
        subprocess.run([binary], cwd=PROJECT_DIR, check=True, timeout=120)

        raw = bytearray()
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw.extend(chunk)
            except BlockingIOError:
                break
    finally:
        os.close(fd)

    events = []
    offset = 0
    while offset + 16 <= len(raw):
        wd, event_mask, cookie, name_len = struct.unpack_from("iIII", raw, offset)
        offset += 16
        name_bytes = bytes(raw[offset:offset + name_len])
        offset += name_len
        name = name_bytes.split(b"\0", 1)[0].decode("utf-8", "replace")
        events.append((event_mask, cookie, name))

    final_names = [f"archive_part_{i:03d}.jsonl" for i in range(1, 4)]
    for final_name in final_names:
        moved_to = [(idx, cookie) for idx, (m, cookie, name) in enumerate(events)
                    if (m & IN_MOVED_TO) and name == final_name]
        assert moved_to, f"{final_name} was not installed by an atomic rename."
        to_index, cookie = moved_to[-1]
        moved_from = [(idx, name) for idx, (m, c, name) in enumerate(events)
                      if idx < to_index and (m & IN_MOVED_FROM) and c == cookie]
        assert moved_from, f"No temporary file rename was observed for {final_name}."
        from_index, temp_name = moved_from[-1]
        assert temp_name != final_name, f"{final_name} was not written through a distinct temporary file."
        assert any(idx < from_index and (m & IN_CREATE) and name == temp_name
                   for idx, (m, _, name) in enumerate(events)), \
            f"Temporary file {temp_name} was not created before producing {final_name}."
        assert any(idx < from_index and (m & IN_CLOSE_WRITE) and name == temp_name
                   for idx, (m, _, name) in enumerate(events)), \
            f"Temporary file {temp_name} was not closed before being renamed to {final_name}."


# Preserve the original final-state assertions and additionally compare every
# archived object to the records derived from the actual initial input files.
initial_expected = expected_from_logs()
validate_archive(initial_expected, require_original_counts=True)

# Require a real buildable Rust application, then exercise the built executable
# on fresh unpredictable recursive inputs and observe its atomic rename behavior.
binary = build_binary()
challenge_expected = install_challenge_logs()
assert len(challenge_expected) == 23
clear_archive()
run_with_atomic_write_watch(binary)
validate_archive(challenge_expected)
PY_EOF

if python3 /tmp/verify_archiver.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
