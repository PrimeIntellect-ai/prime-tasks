#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
SUSPECT_FILE = "/app/suspect_audio.wav"


def run_detector(*args, cwd=None):
    return subprocess.run(
        [DETECTOR_SCRIPT, *args],
        cwd=cwd,
        capture_output=True,
        timeout=5,
    )


def wav_chunk(chunk_id, payload):
    padding = b"\x00" if len(payload) % 2 else b""
    return chunk_id + struct.pack("<I", len(payload)) + payload + padding


def make_wav(path, evil, prefix_size):
    fmt = wav_chunk(
        b"fmt ",
        struct.pack("<HHIIHH", 1, 1, 44100, 88200, 2, 16),
    )
    prefix = wav_chunk(b"JUNK", bytes((i * 37 + 11) % 256 for i in range(prefix_size)))
    data = wav_chunk(b"data", bytes((i * 19 + 3) % 256 for i in range(24)))

    # Both variants have identical physical lengths and the same WvPt chunk ID.
    # Only the vulnerable little-endian size field differs.
    body = b"payload!"
    if evil:
        target = b"WvPt" + b"\xff\xff\xff\xff" + body
    else:
        target = wav_chunk(b"WvPt", body)

    riff_body = b"WAVE" + fmt + prefix + data + target
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(riff_body)) + riff_body)


def test_detector_script_exists_and_executable():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"
    assert os.access(DETECTOR_SCRIPT, os.X_OK), f"Detector script at {DETECTOR_SCRIPT} is not executable"


def test_detector_on_corpora():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.wav')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.wav')]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    clean_failed = []
    for clean_file in clean_files:
        result = subprocess.run([DETECTOR_SCRIPT, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(clean_file))

    evil_failed = []
    for evil_file in evil_files:
        result = subprocess.run([DETECTOR_SCRIPT, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(evil_file))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed[:5])}{'...' if len(clean_failed) > 5 else ''}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed[:5])}{'...' if len(evil_failed) > 5 else ''}")

    assert not errors, " | ".join(errors)


def test_detector_on_suspect_audio():
    assert os.path.isfile(SUSPECT_FILE), f"Suspect audio missing: {SUSPECT_FILE}"
    assert run_detector(SUSPECT_FILE).returncode == 1


def test_detector_on_unseen_randomly_named_wavs():
    with tempfile.TemporaryDirectory(prefix="wav-verification-") as td:
        cases = []
        for prefix_size in (0, 2, 10, 32, 78):
            for evil in (False, True):
                path = os.path.join(td, secrets.token_hex(12) + ".wav")
                make_wav(path, evil, prefix_size)
                cases.append((path, 1 if evil else 0))

        # Names carry no class label, paths are outside either supplied corpus,
        # offsets vary, and paired files have equal lengths.
        for path, expected in cases:
            result = run_detector(path)
            assert result.returncode == expected, (
                f"Detector returned {result.returncode} for unseen WAV; expected {expected}"
            )


def test_exactly_one_absolute_argument_is_required():
    with tempfile.TemporaryDirectory(prefix="wav-arguments-") as td:
        clean_path = os.path.join(td, secrets.token_hex(12) + ".wav")
        evil_path = os.path.join(td, secrets.token_hex(12) + ".wav")
        make_wav(clean_path, False, 6)
        make_wav(evil_path, True, 6)

        assert run_detector().returncode != 0, "Detector accepted zero arguments"
        assert run_detector(clean_path, evil_path).returncode != 0, "Detector accepted two arguments"
        assert run_detector(os.path.basename(clean_path), cwd=td).returncode != 0, (
            "Detector accepted a relative path"
        )
        assert run_detector(clean_path).returncode == 0
        assert run_detector(evil_path).returncode == 1
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
