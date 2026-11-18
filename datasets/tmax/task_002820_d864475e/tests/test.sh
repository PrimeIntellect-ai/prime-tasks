#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/chunk_filter.py"
CLEAN_CORPUS_DIR = "/validation/clean"
EVIL_CORPUS_DIR = "/validation/evil"


def run_filter(fpath):
    try:
        return subprocess.run(
            ["python3", SCRIPT_PATH, fpath],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out while processing {os.path.basename(fpath)}")


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Not a file: {SCRIPT_PATH}"


def test_clean_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Missing clean corpus directory: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus: {CLEAN_CORPUS_DIR}"

    failed_files = []
    for fpath in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, fpath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected with exit code != 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Missing evil corpus directory: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus: {EVIL_CORPUS_DIR}"

    bypassed_files = []
    for fpath in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, fpath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(fpath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted with exit code != 1). Offending files: {', '.join(bypassed_files)}")


def test_unlabelled_generated_corpus():
    corpus_dir = tempfile.mkdtemp(prefix="chunk-check-")
    cases = [False] * 100 + [True] * 100

    # Shuffle using unpredictable verifier-time randomness so labels cannot be
    # inferred from file names, directory names, creation order, or position.
    for i in range(len(cases) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        cases[i], cases[j] = cases[j], cases[i]

    expected = {}
    try:
        for is_evil in cases:
            num_records = 10 + secrets.randbelow(91)
            index_offset = 16
            data_offset = index_offset + num_records * 4
            if is_evil:
                file_size = data_offset - (1 + secrets.randbelow(10))
            else:
                file_size = data_offset + 10 + secrets.randbelow(91)

            blob = struct.pack("<4sIII", b"CHNK", num_records, index_offset, data_offset)
            blob += secrets.token_bytes(file_size - len(blob))
            fpath = os.path.join(corpus_dir, secrets.token_hex(16) + ".bin")
            with open(fpath, "wb") as f:
                f.write(blob)

            # Derive the expected result from the same bounds condition used by
            # the legacy reader, rather than trusting a directory label.
            _, parsed_count, parsed_index, _ = struct.unpack("<4sIII", blob[:16])
            expected[fpath] = 1 if parsed_index + parsed_count * 4 > len(blob) else 0

        failures = []
        for fpath in expected:
            actual = run_filter(fpath)
            if actual != expected[fpath]:
                failures.append(f"{os.path.basename(fpath)}: expected {expected[fpath]}, got {actual}")

        if failures:
            pytest.fail(f"Generated corpus misclassified {len(failures)} of {len(expected)} files: " + "; ".join(failures[:10]))
    finally:
        shutil.rmtree(corpus_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
