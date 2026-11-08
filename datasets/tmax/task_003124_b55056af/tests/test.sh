#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import random
import stat
import string
import subprocess
import tarfile
import time

import pytest

EXTRACTED_DIR = "/home/user/extracted_dataset"
SCRIPT_PATH = "/home/user/filter_dataset.sh"
VIDEO_PATH = "/app/experiment_feed.mp4"
ARCHIVE_PATH = "/app/dataset_archive.tar"
EXPECTED_SOURCE_FRAMES = 1729


def video_frame_count():
    proc = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames", "-of", "default=nw=1:nk=1",
            VIDEO_PATH,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    value = proc.stdout.strip()
    assert value.isdigit(), f"Could not determine video frame count: {value!r}"
    return int(value)


def expected_output(status_code, frames):
    if 200 <= status_code <= 299:
        return f"VALID {frames}"
    if status_code >= 400:
        return f"INVALID {frames}"
    return f"UNKNOWN {frames}"


def test_safe_extraction():
    assert os.path.exists(EXTRACTED_DIR), f"Directory {EXTRACTED_DIR} does not exist."
    assert os.path.isdir(EXTRACTED_DIR), f"{EXTRACTED_DIR} is not a directory."

    # Preserve the original checks for the known valid files.
    assert os.path.exists(os.path.join(EXTRACTED_DIR, "valid_data_1.txt")), "valid_data_1.txt was not extracted."
    assert os.path.exists(os.path.join(EXTRACTED_DIR, "valid_data_2.txt")), "valid_data_2.txt was not extracted."

    # Preserve the original checks for the known malicious targets.
    assert not os.path.exists("/tmp/malicious.sh"), "Zip slip vulnerability! /tmp/malicious.sh was extracted."
    assert not os.path.exists("/home/user/escape.txt"), "Zip slip vulnerability! /home/user/escape.txt was extracted."

    root = os.path.realpath(EXTRACTED_DIR)
    expected_files = set()
    unsafe_targets = []

    with tarfile.open(ARCHIVE_PATH, "r") as archive:
        for member in archive.getmembers():
            target = os.path.realpath(os.path.join(root, member.name))
            try:
                inside = os.path.commonpath([root, target]) == root
            except ValueError:
                inside = False

            if inside and member.isfile():
                expected_files.add(os.path.relpath(target, root))
            elif not inside:
                unsafe_targets.append(target)

    actual_entries = set()
    for current_root, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = os.path.join(current_root, name)
            actual_entries.add(os.path.relpath(path, root))

    # This validates both the requested valid-file count and that no extra archive
    # members were placed in the extraction directory.
    assert actual_entries == expected_files, (
        f"Extracted entries differ from the safe regular files in the archive. "
        f"Expected {sorted(expected_files)}, got {sorted(actual_entries)}"
    )
    assert len(actual_entries) == len(expected_files)

    for relative_path in expected_files:
        path = os.path.join(root, relative_path)
        mode = os.lstat(path).st_mode
        assert stat.S_ISREG(mode), f"Expected a regular extracted file: {path}"
        assert not os.path.islink(path), f"Extracted file must not be a symlink: {path}"

    # Check every traversal destination derived from the archive, not just the two
    # historically hard-coded locations.
    for target in unsafe_targets:
        assert not os.path.lexists(target), f"Unsafe archive member was extracted to {target}"


def test_filter_dataset_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_filter_dataset_uses_flock():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "flock" in content, "The script does not appear to use 'flock'."
    assert "/tmp/filter.lock" in content, "The script does not appear to lock '/tmp/filter.lock'."


def test_filter_dataset_obeys_the_lock():
    frames = video_frame_count()
    lock_file = open("/tmp/filter.lock", "a+")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = subprocess.Popen(
        [SCRIPT_PATH, "[00000000] 200 /path/to/file.dat"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        time.sleep(0.25)
        assert proc.poll() is None, "Script did not wait for the held /tmp/filter.lock lock."
    finally:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()

    stdout, stderr = proc.communicate(timeout=5)
    assert proc.returncode == 0, stderr
    assert stdout.strip() == expected_output(200, frames)


def test_fuzz_equivalence_filter_dataset():
    frames = video_frame_count()
    # The rebuilt source intentionally differs from the illustrative count in the
    # instruction, preventing that example from serving as the answer.
    assert frames == EXPECTED_SOURCE_FRAMES, "The source video was modified."

    random.seed(42)
    cases = [199, 200, 201, 298, 299, 300, 399, 400, 401, 599]
    cases.extend(random.randint(100, 599) for _ in range(4990))

    for status_code in cases:
        timestamp = f"{random.randint(0, 99999999):08d}"
        random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
        log_entry = f"[{timestamp}] {status_code} /path/to/{random_str}.dat"

        proc = subprocess.run(
            [SCRIPT_PATH, log_entry], capture_output=True, text=True, timeout=5
        )
        assert proc.returncode == 0, (
            f"Unexpected return code on input {log_entry!r}: {proc.returncode}; "
            f"stderr={proc.stderr!r}"
        )
        assert proc.stdout.strip() == expected_output(status_code, frames), (
            f"Output mismatch on input {log_entry!r}. Expected "
            f"{expected_output(status_code, frames)!r}, got {proc.stdout.strip()!r}"
        )


def test_parallel_invocations():
    frames = video_frame_count()
    statuses = [100, 199, 200, 250, 299, 300, 399, 400, 500, 599] * 3
    processes = []
    for index, status_code in enumerate(statuses):
        entry = f"[{index:08d}] {status_code} /path/to/parallel_{index}.dat"
        processes.append((status_code, subprocess.Popen(
            [SCRIPT_PATH, entry], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )))

    for status_code, proc in processes:
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, stderr
        assert stdout.strip() == expected_output(status_code, frames)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
