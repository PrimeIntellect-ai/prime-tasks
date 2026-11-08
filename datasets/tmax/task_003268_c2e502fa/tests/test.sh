#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest

CLASSIFIER = "/home/user/classifier.py"
ELF_HEADER = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00"
EXPECTED_PAYLOAD = ELF_HEADER + b"POST /upload?path=../../../../etc/shadow HTTP/1.1"
EXPECTED_PAYLOAD += b"\x00" * (300 - len(EXPECTED_PAYLOAD))


def decode_video(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video: {path}"
    bits = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        b, g, r = frame.mean(axis=(0, 1))
        if r > 200 and g < 50 and b < 50:
            bits.append(1)
        elif b > 200 and r < 50 and g < 50:
            bits.append(0)
        else:
            pytest.fail(f"Video contains an undecodable frame: {path}")
    cap.release()
    assert bits and len(bits) % 8 == 0, f"Invalid encoded bit count in {path}"
    return bytes(
        sum(bits[i + j] << (7 - j) for j in range(8))
        for i in range(0, len(bits), 8)
    )


def create_mp4(path, payload):
    bits = ''.join(f'{byte:08b}' for byte in payload)
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), 30.0, (10, 10))
    assert writer.isOpened(), f"Could not create hidden test video: {path}"
    red = np.zeros((10, 10, 3), dtype=np.uint8)
    red[:] = (0, 0, 255)
    blue = np.zeros((10, 10, 3), dtype=np.uint8)
    blue[:] = (255, 0, 0)
    for bit in bits:
        writer.write(red if bit == '1' else blue)
    writer.release()


def run_classifier(path):
    result = subprocess.run(
        ["python3", CLASSIFIER, path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Classifier exited with {result.returncode} for {path}: {result.stderr}"
    )
    return result.stdout.strip()


def test_extracted_payload():
    """Verify that the student extracted the payload correctly."""
    payload_path = "/home/user/extracted_payload.elf"
    assert os.path.exists(payload_path), f"Extracted payload not found at {payload_path}"
    assert os.path.isfile(payload_path), "Extracted payload is not a regular file"

    with open(payload_path, "rb") as f:
        data = f.read()

    assert data.startswith(b"\x7fELF"), "Extracted file is not a valid ELF binary"
    assert b"../../../../etc/shadow" in data, (
        "Extracted payload does not contain the expected path traversal string"
    )

    decoded = decode_video("/app/suspicious_upload.mp4")
    assert decoded == EXPECTED_PAYLOAD, "The captured suspicious video was modified"
    assert data == decoded, (
        "Extracted payload does not exactly match the bytes encoded in suspicious_upload.mp4"
    )


def test_classifier_against_corpus():
    """Verify the classifier script against the provided corpus."""
    assert os.path.exists(CLASSIFIER), f"Classifier script not found at {CLASSIFIER}"
    assert os.path.isfile(CLASSIFIER), f"Classifier is not a regular file: {CLASSIFIER}"

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    evil_files = glob.glob(os.path.join(evil_dir, "*.mp4"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.mp4"))

    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"

    evil_bypassed = []
    clean_modified = []
    for path in evil_files:
        try:
            if run_classifier(path) != "EVIL":
                evil_bypassed.append(os.path.basename(path))
        except Exception as exc:
            evil_bypassed.append(f"{os.path.basename(path)} (Error: {exc})")

    for path in clean_files:
        try:
            if run_classifier(path) != "CLEAN":
                clean_modified.append(os.path.basename(path))
        except Exception as exc:
            clean_modified.append(f"{os.path.basename(path)} (Error: {exc})")

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            + ", ".join(clean_modified)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_classifier_against_hidden_directories():
    """Exercise decoding and classification on newly generated, unknown paths."""
    root = tempfile.mkdtemp(prefix="upload_validation_")
    evil_dir = os.path.join(root, "incoming_" + uuid.uuid4().hex)
    clean_dir = os.path.join(root, "review_" + uuid.uuid4().hex)
    os.makedirs(evil_dir)
    os.makedirs(clean_dir)

    nonce = uuid.uuid4().hex.encode("ascii")
    evil_payloads = [
        ELF_HEADER + b"GET /download?name=../../private/config " + nonce,
        ELF_HEADER + b"open('/etc/passwd') " + nonce,
        ELF_HEADER + b"cat /etc/shadow " + nonce,
    ]
    clean_payloads = [
        ELF_HEADER + b"Benign diagnostic program " + nonce,
        ELF_HEADER + b"Normal media helper version 1.0 " + nonce,
        b"NOT_AN_ELF ../../../../etc/shadow " + nonce,
    ]

    cases = []
    for payload in evil_payloads:
        path = os.path.join(evil_dir, uuid.uuid4().hex + ".mp4")
        create_mp4(path, payload)
        cases.append((path, "EVIL"))
    for payload in clean_payloads:
        path = os.path.join(clean_dir, uuid.uuid4().hex + ".mp4")
        create_mp4(path, payload)
        cases.append((path, "CLEAN"))

    for path, expected in cases:
        assert decode_video(path) in evil_payloads + clean_payloads
        actual = run_classifier(path)
        assert actual == expected, f"Expected {expected} for hidden upload {path}, got {actual!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
