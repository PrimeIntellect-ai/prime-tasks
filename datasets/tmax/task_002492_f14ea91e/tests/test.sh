#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import glob
import os
import secrets
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/validate"
VIDEO_PATH = "/app/test_sequence.mp4"


def run_validator(video, patch, *extra):
    return subprocess.run(
        [EXECUTABLE, video, patch, *extra],
        capture_output=True,
        timeout=10,
    )


def frame_count(video):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames",
            "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames",
            "-of", "default=nokey=1:noprint_wrappers=1",
            video,
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=15,
    )
    return int(result.stdout.strip())


def write_patch(path, frame, remainder, crc=None):
    if crc is None:
        crc = binascii.crc32(remainder) & 0xFFFFFFFF
    with open(path, "wb") as f:
        f.write(f"FRAME {frame}\nCRC32 {crc:08x}\n".encode("ascii"))
        f.write(remainder)


def test_validate_executable_exists():
    executable = "/home/user/validate"
    assert os.path.isfile(executable), f"Executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."


def test_adversarial_corpus():
    executable = "/home/user/validate"
    video_path = "/app/test_sequence.mp4"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = sorted(glob.glob(os.path.join(clean_dir, "*")))
    evil_files = sorted(glob.glob(os.path.join(evil_dir, "*")))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    clean_rejected = []
    for clean_file in clean_files:
        result = subprocess.run([executable, video_path, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([executable, video_path, evil_file], capture_output=True)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(evil_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_exact_argument_count():
    invocations = [
        [EXECUTABLE],
        [EXECUTABLE, VIDEO_PATH],
        [EXECUTABLE, VIDEO_PATH, "/app/corpus/clean/patch1.txt", "extra"],
    ]
    for command in invocations:
        result = subprocess.run(command, capture_output=True, timeout=10)
        assert result.returncode != 0, f"Accepted invalid argument count: {command}"


def test_unseen_randomized_patches_and_dynamic_video_bounds():
    with tempfile.TemporaryDirectory(prefix="validator-check-") as work:
        generated_video = os.path.join(work, uuid.uuid4().hex + ".mp4")
        requested_frames = secrets.randbelow(9) + 5
        subprocess.run(
            [
                "ffmpeg", "-v", "error", "-f", "lavfi",
                "-i", "testsrc=size=64x64:rate=8",
                "-frames:v", str(requested_frames),
                "-c:v", "mpeg4", "-y", generated_video,
            ],
            check=True,
            timeout=30,
        )

        videos = [VIDEO_PATH, generated_video]
        cases = []
        for video in videos:
            total = frame_count(video)
            assert total > 1
            token = secrets.token_hex(18).encode("ascii")
            valid_remainder = b"@@ -2,1 +2,2 @@\n+overlay-" + token + b"\n"

            valid_path = os.path.join(work, uuid.uuid4().hex)
            write_patch(valid_path, secrets.randbelow(total), valid_remainder)
            cases.append((video, valid_path, True))

            boundary_path = os.path.join(work, uuid.uuid4().hex)
            write_patch(boundary_path, total - 1, b"@@ final @@\n+" + token)
            cases.append((video, boundary_path, True))

            too_high_path = os.path.join(work, uuid.uuid4().hex)
            write_patch(too_high_path, total, valid_remainder)
            cases.append((video, too_high_path, False))

            negative_path = os.path.join(work, uuid.uuid4().hex)
            write_patch(negative_path, -1, valid_remainder)
            cases.append((video, negative_path, False))

            bad_crc_path = os.path.join(work, uuid.uuid4().hex)
            correct_crc = binascii.crc32(valid_remainder) & 0xFFFFFFFF
            write_patch(bad_crc_path, 0, valid_remainder, (correct_crc ^ 0x01010101) & 0xFFFFFFFF)
            cases.append((video, bad_crc_path, False))

            bad_header_path = os.path.join(work, uuid.uuid4().hex)
            write_patch(bad_header_path, 0, b"++ not-a-diff-header\n" + token)
            cases.append((video, bad_header_path, False))

            trailing_tamper_path = os.path.join(work, uuid.uuid4().hex)
            original = b"@@ header @@\n+original"
            crc_before_tamper = binascii.crc32(original) & 0xFFFFFFFF
            write_patch(trailing_tamper_path, 0, original + b"-unchecksummed-tail", crc_before_tamper)
            cases.append((video, trailing_tamper_path, False))

        for video, patch, expected_valid in cases:
            result = run_validator(video, patch)
            if expected_valid:
                assert result.returncode == 0, f"Rejected generated valid patch {patch}"
            else:
                assert result.returncode != 0, f"Accepted generated invalid patch {patch}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
