#!/bin/bash
set -e
mkdir -p /logs/verifier

TEST_DIR=$(mktemp -d /tmp/wal-verifier.XXXXXX)
chmod 700 "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

cat << 'TEST_EOF' > "$TEST_DIR/test_final_state.py"
import os
import random
import secrets
import struct
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/wal_classifier.sh"
CLEAN_CORPUS_DIR = "/app/hidden_corpus/clean/"
EVIL_CORPUS_DIR = "/app/hidden_corpus/evil/"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def run_classifier(path):
    try:
        return subprocess.run(
            [SCRIPT_PATH, path], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_adversarial_corpus_classification():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Cannot run test, valid executable script missing at {SCRIPT_PATH}")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    clean_misclassified = []
    for cf in clean_files:
        if run_classifier(cf) != 0:
            clean_misclassified.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if run_classifier(ef) != 1:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}{'...' if len(evil_bypassed) > 5 else ''}")
    if clean_misclassified:
        errors.append(f"{len(clean_misclassified)} of {len(clean_files)} clean modified (misclassified): {', '.join(clean_misclassified[:5])}{'...' if len(clean_misclassified) > 5 else ''}")

    if errors:
        pytest.fail(" | ".join(errors))


def write_generated_wal(path, poisoned):
    count = secrets.randbelow(11) + 5
    poison_index = secrets.randbelow(count) if poisoned else -1
    with open(path, "wb") as f:
        for index in range(count):
            if index == poison_index:
                typ, length = 0xFF, 13
            else:
                typ = secrets.randbelow(0xFF)
                length = secrets.randbelow(50) + 1
            f.write(struct.pack("<BH", typ, length))
            f.write(os.urandom(length))


def test_classification_on_neutral_random_paths():
    if not os.path.exists(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail(f"Cannot run test, valid executable script missing at {SCRIPT_PATH}")

    cases = [False] * 15 + [True] * 15
    random.SystemRandom().shuffle(cases)
    failures = []

    with tempfile.TemporaryDirectory(prefix="wal_eval_") as corpus_dir:
        generated = []
        for poisoned in cases:
            path = os.path.join(corpus_dir, secrets.token_hex(16) + ".wal")
            write_generated_wal(path, poisoned)
            generated.append((path, 1 if poisoned else 0))

        random.SystemRandom().shuffle(generated)
        for path, expected in generated:
            actual = run_classifier(path)
            if actual != expected:
                failures.append(
                    f"{os.path.basename(path)} expected exit {expected}, got "
                    f"{'timeout' if actual is None else actual}"
                )

    if failures:
        pytest.fail(
            f"{len(failures)} of {len(generated)} neutral-path generated WALs "
            f"misclassified: {'; '.join(failures[:5])}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$TEST_DIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
