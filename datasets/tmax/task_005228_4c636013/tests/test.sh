#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest


def test_storage_setup():
    img_path = "/home/user/capacity_data.img"
    mnt_path = "/home/user/mnt/capacity"
    fstab_path = "/home/user/fstab_mock"

    # Check image file
    assert os.path.isfile(img_path), f"Image file not found at {img_path}"
    assert os.path.getsize(img_path) == 100 * 1024 * 1024, \
        f"Expected a 100MB image, got {os.path.getsize(img_path)} bytes"

    # Check if it's ext4
    file_output = subprocess.check_output(["file", img_path]).decode("utf-8")
    assert "ext4 filesystem" in file_output.lower(), f"Image is not an ext4 filesystem: {file_output}"

    # Check if mounted
    mount_output = subprocess.check_output(["mount"]).decode("utf-8")
    assert mnt_path in mount_output, f"Mount point {mnt_path} is not mounted"

    # Check fstab_mock
    assert os.path.isfile(fstab_path), f"fstab_mock not found at {fstab_path}"
    with open(fstab_path, "r") as f:
        fstab_content = f.read()

    found_fstab_entry = False
    for line in fstab_content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 4:
            if parts[0] == img_path and parts[1] == mnt_path and parts[2] == "ext4":
                opts = parts[3].split(",")
                if "noexec" in opts and "nodev" in opts:
                    found_fstab_entry = True
                    break

    assert found_fstab_entry, f"Correct fstab entry not found in {fstab_path}"


def expected_events(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open test video {video_path}"
    bright = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        bright.append(float(frame.mean()) > 200.0)
    cap.release()
    assert bright, "Test video had no frames"
    return sum(value and (i == 0 or not bright[i - 1]) for i, value in enumerate(bright))


def assert_video_result(script_path, expected):
    json_path = "/home/user/mnt/capacity/access_counts.json"
    if os.path.exists(json_path):
        os.remove(json_path)
    subprocess.run(["python3", script_path], check=True, timeout=120)
    assert os.path.isfile(json_path), f"JSON output not generated at {json_path}"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} contains invalid JSON")
    assert set(data) == {"door_open_events"}, \
        f"Expected a single door_open_events key, got {set(data)}"
    assert type(data["door_open_events"]) is int, "door_open_events must be an integer"
    assert data["door_open_events"] == expected, \
        f"Expected {expected} door_open_events, got {data['door_open_events']}"


def test_physical_access_analysis():
    script_path = "/home/user/analyze_video.py"
    video_path = "/app/server_room_timelapse.mp4"
    json_path = "/home/user/mnt/capacity/access_counts.json"

    assert os.path.isfile(script_path), f"Analysis script not found at {script_path}"

    # Preserve the original assertion about the requested generated output.
    assert os.path.isfile(json_path), f"JSON output not found at {json_path}"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} contains invalid JSON")
    assert "door_open_events" in data, f"'door_open_events' key missing in {json_path}"
    assert data["door_open_events"] == 4, f"Expected 4 door_open_events, got {data['door_open_events']}"

    # Execute the submitted artifact against the supplied video and derive its answer.
    assert_video_result(script_path, expected_events(video_path))

    # Replace the supplied path temporarily with an unpredictable video so a fixed
    # answer cannot pass. The original video is restored even if the test fails.
    backup_path = video_path + ".verifier-backup"
    assert not os.path.exists(backup_path)
    os.replace(video_path, backup_path)
    try:
        event_count = secrets.choice([1, 2, 3, 5, 6, 7])
        event_frames = set(secrets.SystemRandom().sample(list(range(4, 53, 7)), event_count))
        writer = cv2.VideoWriter(
            video_path, cv2.VideoWriter_fourcc(*"mp4v"), 1, (640, 480)
        )
        assert writer.isOpened(), "Could not create verifier probe video"
        for i in range(60):
            level = 255 if i in event_frames else 0
            writer.write(np.full((480, 640, 3), level, dtype=np.uint8))
        writer.release()
        derived = expected_events(video_path)
        assert derived == event_count
        assert_video_result(script_path, derived)
    finally:
        if os.path.exists(video_path):
            os.remove(video_path)
        os.replace(backup_path, video_path)


def test_resource_log_sanitization():
    script_path = "/home/user/sanitize_logs.py"
    assert os.path.isfile(script_path), f"Sanitizer script not found at {script_path}"

    clean_corpus = "/app/corpora/logs/clean/"
    evil_corpus = "/app/corpora/logs/evil/"

    with tempfile.TemporaryDirectory() as test_out_dir:
        # Run on clean corpus
        subprocess.run(["python3", script_path, "--input", clean_corpus, "--output", test_out_dir], check=True)

        clean_files = os.listdir(clean_corpus)
        out_files = os.listdir(test_out_dir)

        missing_clean = set(clean_files) - set(out_files)
        assert not missing_clean, f"{len(missing_clean)} of {len(clean_files)} clean files were incorrectly rejected: {missing_clean}"

        # Clear output dir
        for f in out_files:
            os.remove(os.path.join(test_out_dir, f))

        # Run on evil corpus
        subprocess.run(["python3", script_path, "--input", evil_corpus, "--output", test_out_dir], check=True)

        evil_files = os.listdir(evil_corpus)
        out_files = os.listdir(test_out_dir)

        assert not out_files, f"{len(out_files)} of {len(evil_files)} evil files bypassed sanitization: {out_files}"

    # Exercise a mixed corpus with unpredictable paths and filenames.
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="san-input-") as input_dir, \
         tempfile.TemporaryDirectory(prefix="san-output-") as output_dir:
        clean = {
            f"metrics-{token}.txt": (
                b"2025-01-02T03:04:05Z compute-node-17 37% 4.2GB\n"
                b"2025-01-02T03:05:05Z compute-node-17 38% 4.3GB\n"
            ),
            f"archive-{secrets.token_hex(5)}.log":
                b"2024-12-31T23:59:59Z db-replica-9 100% 16GB\n",
        }
        evil = {
            f"host-shell-{secrets.token_hex(5)}.txt":
                b"2025-01-02T03:04:05Z node-1;touch 40% 2GB\n",
            f"usage-shell-{secrets.token_hex(5)}.txt":
                b"2025-01-02T03:04:05Z node-2 40% 2GB|cat\n",
            f"sql-{secrets.token_hex(5)}.txt":
                b"2025-01-02T03:04:05Z node-3 40% 2GB' OR '1'='1\n",
            f"binary-{secrets.token_hex(5)}.txt":
                b"2025-01-02T03:04:05Z node-4 40% 2GB\xff\x00\n",
        }
        for name, content in {**clean, **evil}.items():
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(content)

        subprocess.run(
            ["python3", script_path, "--input", input_dir, "--output", output_dir],
            check=True,
            timeout=30,
        )

        assert set(os.listdir(output_dir)) == set(clean), \
            f"Sanitizer did not retain exactly the safe files: {os.listdir(output_dir)}"
        for name, expected_content in clean.items():
            output_path = os.path.join(output_dir, name)
            assert os.path.isfile(output_path)
            with open(output_path, "rb") as f:
                assert f.read() == expected_content, f"Sanitizer altered safe file {name}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
