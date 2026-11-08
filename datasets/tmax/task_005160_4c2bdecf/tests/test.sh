#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import struct
import subprocess
import tempfile
import pytest


def test_leak_analysis_content():
    path = "/home/user/leak_analysis.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    expected = "BAZINGA:9F8E7D6C5B4A3928"
    assert content == expected, f"Expected content '{expected}', but got '{content}'"


def test_detector_executable():
    path = "/home/user/detector"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile detector.cpp?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_detector_source():
    source = "/home/user/detector.cpp"
    output = "/tmp/detector_from_source"
    assert os.path.isfile(source), f"Source file {source} does not exist."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", output],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"detector.cpp does not compile:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)


def test_adversarial_corpus():
    detector = "/home/user/detector"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) == 50, f"Expected 50 clean files, found {len(clean_files)}."
    assert len(evil_files) == 50, f"Expected 50 evil files, found {len(evil_files)}."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([detector, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([detector, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def make_wave(frame_count, channels, sample_rate, malicious):
    sample_width = 2
    block_align = channels * sample_width
    byte_rate = sample_rate * block_align
    fmt = struct.pack("<HHIIHH", 1, channels, sample_rate, byte_rate, block_align, 16)
    audio = os.urandom(frame_count * block_align)
    chunks = bytearray()

    if malicious:
        declared_size = random.randint(0x08000000, 0x3fffffff)
        short_body = os.urandom(random.randint(0, 24))
        chunks += b"JUNK" + struct.pack("<I", declared_size) + short_body

    chunks += b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(audio)) + audio
    return b"RIFF" + struct.pack("<I", len(chunks) + 4) + b"WAVE" + chunks


def test_generated_hidden_cases():
    submitted = "/home/user/detector"
    rebuilt = "/tmp/detector_from_source"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    with tempfile.TemporaryDirectory(prefix="wavcases_") as case_dir:
        cases = []
        for malicious in ([False] * 24 + [True] * 24):
            name = secrets.token_hex(12) + ".wav"
            path = os.path.join(case_dir, name)
            data = make_wave(
                frame_count=random.randint(80, 1200),
                channels=random.choice([1, 2]),
                sample_rate=random.choice([8000, 16000, 22050, 44100, 48000]),
                malicious=malicious,
            )
            with open(path, "wb") as f:
                f.write(data)
            cases.append((path, 1 if malicious else 0))

        random.SystemRandom().shuffle(cases)
        failures = []
        for detector in (submitted, rebuilt):
            for path, expected in cases:
                try:
                    result = subprocess.run([detector, path], capture_output=True, timeout=3)
                    actual = result.returncode
                except subprocess.TimeoutExpired:
                    actual = "timeout"
                if actual != expected:
                    failures.append(
                        f"{os.path.basename(detector)} returned {actual} for {os.path.basename(path)}; expected {expected}"
                    )

        assert not failures, "Generated WAV failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
