#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import random
import secrets
import subprocess
import tempfile

import pytest

CLEAN_DIR = '/app/corpus/clean'
EVIL_DIR = '/app/corpus/evil'
EXECUTABLE = '/home/user/config_filter'
SOURCE = '/home/user/config_filter.cpp'


def run_filter(*args):
    return subprocess.run(
        [EXECUTABLE, *args],
        capture_output=True,
        timeout=5,
    )


def encode_rle(text):
    data = bytearray()
    i = 0
    while i < len(text):
        j = i + 1
        while j < len(text) and text[j] == text[i] and j - i < 255:
            j += 1
        data.extend((j - i, ord(text[i])))
        i = j
    return bytes(data)


def test_executable_exists():
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File at {EXECUTABLE} is not a compiled executable"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    clean_failed = []
    for f in clean_files:
        result = run_filter(f)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_bypassed = []
    for f in evil_files:
        result = run_filter(f)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(f))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def test_generated_unlabelled_patches():
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    rand_text = lambda n: ''.join(secrets.choice(alphabet) for _ in range(n))

    valid_cases = [
        encode_rle(rand_text(10)),                         # exact minimum length
        encode_rle(rand_text(37)),
        encode_rle('A' * 10),                             # expansion, not file size, reaches minimum
        encode_rle('A' * 3 + 'B' * 7 + 'C' * 11),        # several nontrivial runs
        encode_rle('Z' * 255),                            # maximum one-byte run count
        encode_rle('key=value_12345'),
    ]

    invalid_cases = [
        encode_rle(rand_text(9)),                         # compressed file is >10 bytes, text is short
        b'',                                              # empty decompression is too short
        encode_rle(rand_text(12) + 'drop_database' + rand_text(8)),
        encode_rle('drop_database'),
        encode_rle(rand_text(20)) + bytes([secrets.randbelow(256)]),  # incomplete pair
        encode_rle('A' * 10) + bytes([1, 0x80]),          # non-ASCII after otherwise valid text
        bytes([10, 0xff]),                                # non-ASCII run of sufficient length
    ]

    cases = [(data, True) for data in valid_cases] + [(data, False) for data in invalid_cases]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix='cf_cases_') as directory:
        created = []
        for data, expected_valid in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, 'wb') as f:
                f.write(data)
            created.append((path, expected_valid))

        random.SystemRandom().shuffle(created)
        failures = []
        for path, expected_valid in created:
            result = run_filter(path)
            actual_valid = result.returncode == 0
            if actual_valid != expected_valid:
                failures.append(
                    f"{os.path.basename(path)} expected {'accept' if expected_valid else 'reject'}, "
                    f"got return code {result.returncode}"
                )

        assert not failures, 'Generated patch failures: ' + ' | '.join(failures)


def test_exactly_one_argument_required():
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert clean_files, "No clean files available for argument testing."
    assert run_filter().returncode != 0, "Executable accepted no patch argument"
    assert run_filter(clean_files[0], clean_files[0]).returncode != 0, "Executable accepted more than one patch argument"


def test_file_locking():
    """Verify that the program fails to run if the lock file is already held."""
    lock_file = '/tmp/config_filter.lock'

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "No clean files available for lock testing."
    test_file = clean_files[0]

    with open(lock_file, 'w') as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock_acquired = True
        except BlockingIOError:
            lock_acquired = False

        assert lock_acquired, "Test setup failed: could not acquire lock."
        result = run_filter(test_file)
        fcntl.flock(f, fcntl.LOCK_UN)

    assert result.returncode != 0, "Executable bypassed file locking: it succeeded even when the lock was held by another process."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
