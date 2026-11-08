#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

DETECTOR_PATH = "/home/user/detector"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"

def test_detector_exists_and_executable():
    assert os.path.exists(DETECTOR_PATH), f"Detector script not found at {DETECTOR_PATH}"
    assert os.path.isfile(DETECTOR_PATH), f"{DETECTOR_PATH} is not a file"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector script at {DETECTOR_PATH} is not executable"

def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus: {CLEAN_CORPUS_DIR}"

    failed_clean = []

    for filepath in clean_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(filepath))

    if failed_clean:
        pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_clean)}")

def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus: {EVIL_CORPUS_DIR}"

    failed_evil = []

    for filepath in evil_files:
        result = subprocess.run([DETECTOR_PATH, filepath], capture_output=True)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(filepath))

    if failed_evil:
        pytest.fail(f"{len(failed_evil)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_evil)}")

def test_randomized_unlabelled_archives():
    def token(n=10):
        return secrets.token_hex(n)

    def valid_config():
        return json.dumps({token(4): token(8)}, separators=(",", ":")).encode("utf-16le")

    def write_archive(path, config, files):
        with open(path, "wb") as f:
            f.write(b"FARCHV")
            f.write(config)
            f.write(b"\x00\x00")
            for name, data in files:
                name_b = name.encode("utf-8")
                f.write(struct.pack("<I", len(name_b)))
                f.write(name_b)
                f.write(struct.pack("<Q", len(data)))
                f.write(data)

    with tempfile.TemporaryDirectory(prefix="archive-check-") as case_dir:
        cases = []

        def new_path():
            return os.path.join(case_dir, token(12))

        # Safe and unsafe cases deliberately share one randomly named directory
        # and have opaque randomized basenames.
        p = new_path()
        write_archive(p, valid_config(), [(token(5) + ".wal", secrets.token_bytes(17))])
        cases.append((p, True))

        p = new_path()
        write_archive(p, valid_config(), [(token(4) + "/" + token(5) + ".gcode", secrets.token_bytes(31))])
        cases.append((p, True))

        p = new_path()
        write_archive(p, valid_config(), [("../" + token(6), secrets.token_bytes(13))])
        cases.append((p, False))

        p = new_path()
        write_archive(p, valid_config(), [("/" + token(6) + "/" + token(5), secrets.token_bytes(19))])
        cases.append((p, False))

        p = new_path()
        write_archive(p, valid_config(), [("..\\" + token(6), secrets.token_bytes(23))])
        cases.append((p, False))

        p = new_path()
        malformed = bytes(secrets.randbelow(255) + 1 for _ in range(3))
        write_archive(p, malformed, [(token(5), secrets.token_bytes(7))])
        cases.append((p, False))

        p = new_path()
        with open(p, "wb") as f:
            f.write(b"FARCHV")
            f.write(valid_config())
            f.write(b"\x00\x00")
            f.write(struct.pack("<I", 0xFFFFFFFF))
            f.write(secrets.token_bytes(1 + secrets.randbelow(16)))
        cases.append((p, False))

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for path, should_be_safe in cases:
            result = subprocess.run([DETECTOR_PATH, path], capture_output=True)
            accepted = result.returncode == 0
            if accepted != should_be_safe:
                failures.append((os.path.basename(path), "safe" if should_be_safe else "unsafe", result.returncode))

        assert not failures, f"Detector misclassified randomized unlabelled archives: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
