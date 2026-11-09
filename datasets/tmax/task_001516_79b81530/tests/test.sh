#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import ctypes
import json
import os
import select
import shutil
import struct
import subprocess
import tarfile
import time
import uuid

import pytest

TAR_PATH = "/app/final_backup.tar.gz"
EXTRACT_DIR = "/tmp/verify_final"
GO_CODE_PATH = "/app/archiver/main.go"
ARCHIVE_STAGE = "/app/archive_stage"
LEGACY_LOGS = "/app/legacy_logs"

initial_stage_entries = None
dynamic_expected = None
dynamic_actual = None
inotify_events = None


def derive_log_lines(root):
    result = []
    for current, dirs, files in os.walk(root):
        dirs.sort()
        files.sort()
        for name in files:
            path = os.path.join(current, name)
            with open(path, "rb") as f:
                raw = f.read()

            if raw.startswith(b"\xff\xfe"):
                text = raw[2:].decode("utf-16le")
            elif raw.startswith(b"\xfe\xff"):
                text = raw[2:].decode("utf-16be")
            elif len(raw) >= 4 and sum(raw[1::2].count(x) for x in []) == 0 and raw[1::2].count(0) > len(raw[1::2]) // 2:
                text = raw.decode("utf-16le")
            else:
                try:
                    text = raw.decode("utf-8")
                except UnicodeDecodeError:
                    text = raw.decode("iso-8859-1")

            result.extend(line for line in text.splitlines() if "CRITICAL_BACKUP_FAILURE" in line)
    return result


def derive_video_count(path):
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json", path],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    frame_size = width * height

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vsync", "0",
         "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout
    assert len(decoded) % frame_size == 0, "Decoded video ended with a partial frame"

    count = 0
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        if sum(frame) / frame_size > 100:
            count += 1
    return count


def read_inotify(fd, events):
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return
        if not data:
            return
        pos = 0
        while pos < len(data):
            wd, mask, cookie, length = struct.unpack_from("iIII", data, pos)
            pos += 16
            name = data[pos:pos + length].split(b"\0", 1)[0].decode("utf-8", "replace")
            pos += length
            events.append((mask, cookie, name))


@pytest.fixture(scope="module", autouse=True)
def prepare_and_execute_submission():
    global initial_stage_entries, dynamic_expected, dynamic_actual, inotify_events

    assert os.path.isfile(TAR_PATH), f"Tarball not found at {TAR_PATH}"
    assert os.path.isfile(GO_CODE_PATH), f"Go source code not found at {GO_CODE_PATH}"
    assert os.path.isfile("/app/archiver/go.mod"), "Go module file /app/archiver/go.mod is missing"
    assert os.path.isdir(ARCHIVE_STAGE), "/app/archive_stage is missing"
    initial_stage_entries = sorted(os.listdir(ARCHIVE_STAGE))

    if os.path.exists(EXTRACT_DIR):
        shutil.rmtree(EXTRACT_DIR)
    os.makedirs(EXTRACT_DIR)
    with tarfile.open(TAR_PATH, "r:gz") as tar:
        for member in tar.getmembers():
            normalized = os.path.normpath(member.name)
            assert not os.path.isabs(member.name) and normalized != ".." and not normalized.startswith("../"), "Unsafe tar member"
            assert member.isdir() or member.isfile(), "Tarball may contain only directories and regular files"
        tar.extractall(EXTRACT_DIR)

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/submitted_archiver", "."],
        cwd="/app/archiver", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert build.returncode == 0, f"Go program did not build:\n{build.stdout}\n{build.stderr}"

    token = uuid.uuid4().hex
    backup_logs = f"/tmp/legacy_logs_original_{token}"
    os.rename(LEGACY_LOGS, backup_logs)
    os.makedirs(os.path.join(LEGACY_LOGS, "deep", "nested"))
    try:
        with open(os.path.join(LEGACY_LOGS, "latin.log"), "wb") as f:
            f.write((
                "INFO café\n"
                f"CRITICAL_BACKUP_FAILURE latin café {token}\n"
                "WARNING ordinary\n"
            ).encode("iso-8859-1"))
        with open(os.path.join(LEGACY_LOGS, "deep", "utf16.log"), "wb") as f:
            f.write((
                f"CRITICAL_BACKUP_FAILURE utf16 alpha {token}\n"
                "INFO completed\n"
            ).encode("utf-16le"))
        with open(os.path.join(LEGACY_LOGS, "deep", "nested", "more.log"), "wb") as f:
            f.write((
                "DEBUG unrelated\n"
                f"prefix CRITICAL_BACKUP_FAILURE nested {token} suffix\n"
            ).encode("utf-16le"))
        dynamic_expected = derive_log_lines(LEGACY_LOGS)

        for entry in os.listdir(ARCHIVE_STAGE):
            path = os.path.join(ARCHIVE_STAGE, entry)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

        libc = ctypes.CDLL(None, use_errno=True)
        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        assert fd >= 0, "Unable to initialize inotify"
        watch_mask = 0x00000100 | 0x00000008 | 0x00000040 | 0x00000080
        wd = libc.inotify_add_watch(fd, ARCHIVE_STAGE.encode(), watch_mask)
        assert wd >= 0, "Unable to watch archive_stage"

        inotify_events = []
        process = subprocess.Popen(
            ["/tmp/submitted_archiver"], cwd="/app/archiver",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        while process.poll() is None:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                read_inotify(fd, inotify_events)
        stdout, stderr = process.communicate()
        time.sleep(0.05)
        read_inotify(fd, inotify_events)
        os.close(fd)
        assert process.returncode == 0, f"Go program failed:\n{stdout}\n{stderr}"

        output_path = os.path.join(ARCHIVE_STAGE, "aggregated.log")
        assert os.path.isfile(output_path), "Executing the Go program did not create aggregated.log"
        with open(output_path, "r", encoding="utf-8") as f:
            dynamic_actual = [line.strip() for line in f if line.strip()]
    finally:
        if os.path.exists(LEGACY_LOGS):
            shutil.rmtree(LEGACY_LOGS)
        os.rename(backup_logs, LEGACY_LOGS)

    yield
    shutil.rmtree(EXTRACT_DIR, ignore_errors=True)


def extracted_regular_files():
    result = []
    for root, dirs, files in os.walk(EXTRACT_DIR):
        for name in files:
            result.append(os.path.join(root, name))
    return result


def get_extracted_file_path(filename):
    matches = [p for p in extracted_regular_files() if os.path.basename(p) == filename]
    assert len(matches) == 1, f"Expected exactly one {filename} in tarball, found {len(matches)}"
    return matches[0]


def test_archive_stage_contains_exactly_two_files():
    assert initial_stage_entries == ["aggregated.log", "light_frames.txt"], \
        f"archive_stage must contain exactly aggregated.log and light_frames.txt; found {initial_stage_entries}"


def test_tarball_contents():
    files = extracted_regular_files()
    names = sorted(os.path.basename(path) for path in files)
    assert names == ["aggregated.log", "light_frames.txt"], \
        f"Tarball must contain exactly the two required files; found {names}"


def test_aggregated_log():
    log_path = get_extracted_file_path("aggregated.log")
    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "CRITICAL_BACKUP_FAILURE disk 0x1A",
        "CRITICAL_BACKUP_FAILURE network drop",
    ]
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in aggregated.log"
    assert len(lines) == 2, f"aggregated.log should contain exactly 2 lines, found {len(lines)}"


def test_executed_go_program_parses_recursive_mixed_encodings():
    assert collections.Counter(dynamic_actual) == collections.Counter(dynamic_expected), \
        f"Executed archiver output mismatch. Expected {dynamic_expected!r}, got {dynamic_actual!r}"


def test_light_frames_metric():
    count_path = get_extracted_file_path("light_frames.txt")
    with open(count_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content.isdigit(), f"Content of light_frames.txt is not an integer: '{content}'"
    pred_count = int(content)

    ground_truth = 25
    error = abs(pred_count - ground_truth)
    assert error <= 2, f"Metric failed: Count error {error} exceeds threshold of 2 (Predicted: {pred_count}, Expected: {ground_truth})"

    recomputed = derive_video_count("/app/audit.mp4")
    assert pred_count == recomputed, \
        f"light_frames.txt must equal the recomputed frame count (Predicted: {pred_count}, Recomputed: {recomputed})"


def test_go_code_atomic_write():
    with open(GO_CODE_PATH, "r", encoding="utf-8") as f:
        code = f.read()
    assert "os.Rename" in code or "Rename(" in code, "Atomic write pattern (Rename) missing in Go code."

    IN_CREATE = 0x00000100
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_TO = 0x00000080
    aggregate_events = [(mask, name) for mask, cookie, name in inotify_events if name == "aggregated.log"]
    assert any(mask & IN_MOVED_TO for mask, name in aggregate_events), \
        f"aggregated.log was not installed by a rename; observed events: {inotify_events!r}"
    assert not any(mask & IN_CREATE for mask, name in aggregate_events), \
        "aggregated.log was created directly instead of being atomically renamed into place"
    moved_index = max(i for i, (mask, cookie, name) in enumerate(inotify_events)
                      if name == "aggregated.log" and mask & IN_MOVED_TO)
    assert not any(name == "aggregated.log" and mask & IN_CLOSE_WRITE
                   for mask, cookie, name in inotify_events[moved_index + 1:]), \
        "aggregated.log was modified directly after the atomic rename"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
