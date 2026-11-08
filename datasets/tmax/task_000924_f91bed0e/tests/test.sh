#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import struct
import subprocess
import tempfile

import pytest


def run_sanitizer(path, *args):
    return subprocess.run([path, *args], capture_output=True, timeout=10)


def test_reference_frame_extracted():
    frame_path = "/home/user/reference_frame.raw"
    assert os.path.exists(frame_path), f"Missing reference_frame.raw at {frame_path}"
    assert os.path.isfile(frame_path), f"Not a file: {frame_path}"

    size = os.path.getsize(frame_path)
    expected_size = 640 * 480
    assert size == expected_size, f"Invalid frame size: expected {expected_size}, got {size}. Ensure it is 8-bit grayscale at 640x480."

    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", "/app/experiment.mp4",
            "-ss", "2.500", "-frames:v", "1",
            "-vf", "scale=640:480,format=gray",
            "-f", "rawvideo", "-",
        ],
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not derive reference frame: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == expected_size, "ffmpeg produced an unexpected reference-frame size"
    with open(frame_path, "rb") as submitted:
        actual = submitted.read()
    assert actual == result.stdout, "reference_frame.raw is not the grayscale 640x480 frame at 2.5 seconds"


def test_sanitizer_executable_exists():
    sanitizer_path = "/home/user/sanitizer"
    assert os.path.exists(sanitizer_path), f"Missing sanitizer executable at {sanitizer_path}"
    assert os.path.isfile(sanitizer_path), f"Not a file: {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer is not executable: {sanitizer_path}"

    source_path = "/home/user/sanitizer.cpp"
    assert os.path.exists(source_path), f"Missing sanitizer source at {source_path}"
    assert os.path.isfile(source_path), f"Not a file: {source_path}"
    with open(sanitizer_path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "sanitizer must be a compiled executable"


def test_sanitizer_clean_corpus():
    sanitizer_path = "/home/user/sanitizer"
    clean_dir = "/app/corpora/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.dat"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"

    failed_files = []
    for f in clean_files:
        result = run_sanitizer(sanitizer_path, f)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected). Offending files: {', '.join(failed_files)}")


def test_sanitizer_evil_corpus():
    sanitizer_path = "/home/user/sanitizer"
    evil_dir = "/app/corpora/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.dat"))

    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    bypassed_files = []
    for f in evil_files:
        result = run_sanitizer(sanitizer_path, f)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(f))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted). Offending files: {', '.join(bypassed_files)}")


def make_valid(frame_index, payload):
    return b"SENSORDT" + struct.pack("<II", frame_index, len(payload)) + payload


def test_sanitizer_generated_inputs_at_same_path():
    sanitizer_path = "/home/user/sanitizer"
    rng = random.SystemRandom()

    valid_payloads = [b"", os.urandom(1), os.urandom(17), os.urandom(257), os.urandom(4096)]
    cases = []
    for payload in valid_payloads:
        cases.append((make_valid(rng.randrange(0, 2**32), payload), 0, "valid file"))

    matching_payload = os.urandom(73)
    cases.extend([
        (b"", 1, "empty file"),
        (os.urandom(7), 1, "short file"),
        (os.urandom(15), 1, "15-byte file"),
        (b"SENSORXX" + struct.pack("<II", rng.randrange(0, 2**32), len(matching_payload)) + matching_payload, 1, "bad magic"),
        (b"SENSORDT" + struct.pack("<II", rng.randrange(0, 2**32), 74) + matching_payload, 1, "truncated payload"),
        (b"SENSORDT" + struct.pack("<II", rng.randrange(0, 2**32), 72) + matching_payload, 1, "padded payload"),
        (b"SENSORDT" + struct.pack("<II", rng.randrange(0, 2**32), 0) + os.urandom(1), 1, "junk after zero-length payload"),
        (b"SENSORDT" + struct.pack("<II", rng.randrange(0, 2**32), 0xFFFFFFFF) + os.urandom(8), 1, "impossible declared length"),
    ])
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sanitizer-check-") as directory:
        probe = os.path.join(directory, "probe.dat")
        for data, expected, description in cases:
            with open(probe, "wb") as output:
                output.write(data)
            result = run_sanitizer(sanitizer_path, probe)
            assert result.returncode == expected, (
                f"Sanitizer returned {result.returncode} for {description}; expected {expected}"
            )


def test_sanitizer_requires_exactly_one_argument():
    sanitizer_path = "/home/user/sanitizer"
    assert run_sanitizer(sanitizer_path).returncode != 0, "Sanitizer accepted an invocation with no argument"
    with tempfile.TemporaryDirectory() as directory:
        first = os.path.join(directory, "first.dat")
        second = os.path.join(directory, "second.dat")
        data = make_valid(1, b"")
        for path in (first, second):
            with open(path, "wb") as output:
                output.write(data)
        assert run_sanitizer(sanitizer_path, first, second).returncode != 0, "Sanitizer accepted more than one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
