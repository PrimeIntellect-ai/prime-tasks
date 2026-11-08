#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import secrets
import string
import subprocess

import cv2
import pytest

DETECTOR = "/home/user/detector"


def test_detector_exists():
    detector_path = DETECTOR
    assert os.path.isfile(detector_path), f"Detector binary {detector_path} is missing."
    assert os.access(detector_path, os.X_OK), f"Detector binary {detector_path} is not executable."
    with open(detector_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable binary."


def test_evil_corpus_rejected():
    detector_path = DETECTOR
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, f"No files found in {evil_dir}."

    bypassed_files = []
    for f in evil_files:
        file_path = os.path.join(evil_dir, f)
        result = subprocess.run([detector_path, file_path], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(f)

    assert len(bypassed_files) == 0, f"{len(bypassed_files)} of {len(evil_files)} evil payloads bypassed the detector. Offending files: {', '.join(bypassed_files)}"


def test_clean_corpus_accepted():
    detector_path = DETECTOR
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, f"No files found in {clean_dir}."

    modified_files = []
    for f in clean_files:
        file_path = os.path.join(clean_dir, f)
        result = subprocess.run([detector_path, file_path], capture_output=True)
        if result.returncode != 0:
            modified_files.append(f)

    assert len(modified_files) == 0, f"{len(modified_files)} of {len(clean_files)} clean payloads were flagged. Offending files: {', '.join(modified_files)}"


def recover_key_from_video():
    capture = cv2.VideoCapture("/app/capture.mp4")
    assert capture.isOpened(), "Could not open /app/capture.mp4"
    bits = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        height, width = frame.shape[:2]
        red = int(frame[height // 2, width // 2, 2])
        bits.append(1 if red > 128 else 0)
    capture.release()

    assert len(bits) == 256, f"Expected 256 video frames, got {len(bits)}"
    return bytes(
        sum(bits[byte_index * 8 + bit_index] << (7 - bit_index) for bit_index in range(8))
        for byte_index in range(32)
    )


def test_fresh_randomized_payloads(tmp_path):
    key = recover_key_from_video()

    def lower_filler(length):
        return ''.join(secrets.choice(string.ascii_lowercase) for _ in range(length))

    def valid_code():
        alphabet = string.ascii_uppercase + string.digits
        return ''.join(secrets.choice(alphabet) for _ in range(4))

    cases = [
        (f"EXFIL-{valid_code()}", 1),
        (lower_filler(37) + f"EXFIL-{valid_code()}" + lower_filler(11), 1),
        (lower_filler(97) + f"EXFIL-{valid_code()}" + lower_filler(70), 1),
        (lower_filler(12) + "EXFIL-ABCDE" + lower_filler(9), 1),
        (lower_filler(45) + "EXFIL-abc1" + lower_filler(7), 0),
        (lower_filler(68) + "EXFIL-AB_1" + lower_filler(5), 0),
        (lower_filler(3) + "EXFIL-AB1" + lower_filler(80), 0),
        (lower_filler(33) + "EXFILXAB12" + lower_filler(4), 0),
        (lower_filler(110) + "CLEAN-Z9Q0" + lower_filler(13), 0),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    for plaintext, expected in cases:
        raw = plaintext.encode("ascii")
        encrypted = bytes(value ^ key[index % len(key)] for index, value in enumerate(raw))
        path = tmp_path / (secrets.token_hex(12) + ".dat")
        path.write_text(base64.b64encode(encrypted).decode("ascii"), encoding="ascii")
        try:
            result = subprocess.run([DETECTOR, str(path)], capture_output=True, timeout=5)
        except subprocess.TimeoutExpired:
            failures.append((path.name, expected, "timeout"))
            continue
        if result.returncode != expected:
            failures.append((path.name, expected, result.returncode))

    assert not failures, f"Detector failed fresh decoded/XOR/regex cases: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
