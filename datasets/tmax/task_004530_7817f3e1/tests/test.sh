#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/archiver_cleanup/target/release/log_filter"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
PREFIX = "/mnt/storage_pool_A"


def run_filter(filepath):
    return subprocess.run(
        [BINARY_PATH, filepath],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def record(record_id, mount, size):
    return (
        "[ARCHIVE_RECORD]\n"
        f"ID={record_id}\n"
        f"MOUNT={mount}\n"
        f"SIZE={size}\n"
        "[END_RECORD]\n"
    )


def test_binary_exists():
    """Check that the compiled Rust binary exists."""
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}. Did you run 'cargo build --release'?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", f"Binary at {BINARY_PATH} is not an ELF executable."


def test_evil_corpus_rejected():
    """Check that all files in the evil corpus are rejected (exit code 1)."""
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing at {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1, got something else):\n" + "\n".join(bypassed_files))


def test_clean_corpus_accepted():
    """Check that all files in the clean corpus are accepted (exit code 0)."""
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus."

    rejected_files = []
    for filepath in clean_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            rejected_files.append(os.path.basename(filepath))

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean files rejected (expected exit code 0, got something else):\n" + "\n".join(rejected_files))


def test_generated_hidden_cases():
    """Exercise parsing and policy checks using opaque paths and generated content."""
    nonce = secrets.token_hex(8)
    clean_cases = [
        record(0, PREFIX, 0),
        record(734921, f"{PREFIX}/archive_{nonce}", 184467),
        record(91, f"{PREFIX}/deep/{nonce}/snapshot", 1)
        + record(92, f"{PREFIX}/other/{nonce}/snapshot", 999999),
        "".join(
            record(100000 + i, f"{PREFIX}/bulk/{nonce}/{i}", i * 17)
            for i in range(2000)
        ),
    ]

    valid = record(451, f"{PREFIX}/valid/{nonce}", 4096)
    evil_cases = [
        record(1, f"/mnt/storage_pool_B/{nonce}", 12),
        record(2, f"{PREFIX}/safe/../secret", 12),
        record(3, f"{PREFIX}/safe/..", 12),
        "[ARCHIVE_RECORD]\nID=4\nMOUNT=" + PREFIX + "/missing_size\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nMOUNT=" + PREFIX + "/missing_id\nSIZE=4\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nID=5\nSIZE=4\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nID=6\nMOUNT=" + PREFIX + "/unclosed\nSIZE=4\n",
        "garbage\n" + valid,
        valid + "garbage\n",
        valid + "garbage between records\n" + valid,
        "[ARCHIVE_RECORD]\nID=not_numeric\nMOUNT=" + PREFIX + "/x\nSIZE=4\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nID=8\nMOUNT=" + PREFIX + "/x\nSIZE=not_numeric\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nMOUNT=" + PREFIX + "/wrong_order\nID=9\nSIZE=4\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nID=10\nID=11\nMOUNT=" + PREFIX + "/duplicate\nSIZE=4\n[END_RECORD]\n",
        "[ARCHIVE_RECORD]\nID=12\nMOUNT=relative/path\nSIZE=4\n[END_RECORD]\n",
        valid + record(13, f"{PREFIX}/ok/../bad", 8),
        "[END_RECORD]\n",
    ]

    cases = [(content, 0) for content in clean_cases]
    cases.extend((content, 1) for content in evil_cases)
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix=f"archive_checks_{nonce}_") as directory:
        generated = []
        for content, expected in cases:
            path = os.path.join(directory, secrets.token_hex(16) + ".dat")
            with open(path, "w", encoding="utf-8", newline="") as output:
                output.write(content)
            generated.append((path, expected))

        random.SystemRandom().shuffle(generated)
        for path, expected in generated:
            actual = run_filter(path)
            if actual != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected exit {expected}, got {actual}"
                )

    if failures:
        pytest.fail("Generated classification failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
