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

DETECTOR_PATH = "/home/user/detector"
EVIL_CORPUS_PATH = "/app/corpus/evil/"
CLEAN_CORPUS_PATH = "/app/corpus/clean/"

def run_detector(filepath):
    try:
        return subprocess.run(
            [DETECTOR_PATH, filepath],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {filepath}")

def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector binary missing: {DETECTOR_PATH} should exist."
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary is not executable: {DETECTOR_PATH}"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\\x7fELF", "Detector must be a compiled executable"
    result = subprocess.run(["go", "version", "-m", DETECTOR_PATH], capture_output=True, text=True)
    assert result.returncode == 0 and "go1." in result.stdout, "Detector must be compiled from Go"

def test_detector_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_PATH), f"Evil corpus directory missing: {EVIL_CORPUS_PATH}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_PATH) if os.path.isfile(os.path.join(EVIL_CORPUS_PATH, f))]
    assert len(evil_files) > 0, f"Evil corpus directory {EVIL_CORPUS_PATH} is empty."

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_PATH, filename)
        if run_detector(filepath) != 1:
            bypassed.append(filename)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(bypassed)}")

def test_detector_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_PATH), f"Clean corpus directory missing: {CLEAN_CORPUS_PATH}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_PATH) if os.path.isfile(os.path.join(CLEAN_CORPUS_PATH, f))]
    assert len(clean_files) > 0, f"Clean corpus directory {CLEAN_CORPUS_PATH} is empty."

    modified = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_PATH, filename)
        if run_detector(filepath) != 0:
            modified.append(filename)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/rejected (expected exit code 0). Offending files: {', '.join(modified)}")

def test_detector_on_randomized_neutral_paths():
    cases = []
    clean_functions = [
        "net/http.(*connReader).backgroundRead(...)",
        "runtime.gopark(...)",
        "database/sql.(*DB).connectionOpener(...)",
        "github.com/company/srv/api.(*Server).serve(...)",
    ]

    for _ in range(30):
        gid = secrets.randbelow(900000) + 1
        noise_gid = secrets.randbelow(900000) + 1
        dump = (
            f"goroutine {noise_gid} [running]:\\n"
            f"net/http.(*connReader).backgroundRead(...)\\n\\n"
            f"goroutine {gid} [chan send]:\\n"
            f"github.com/company/srv/worker.flushBuffer(...)\\n"
        )
        cases.append((dump, 1))

    for _ in range(30):
        gid = secrets.randbelow(900000) + 1
        state = random.choice(["running", "IO wait", "select", "sleep"])
        function = random.choice(clean_functions)
        dump = f"goroutine {gid} [{state}]:\\n{function}\\n"
        cases.append((dump, 0))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="goroutine-inputs-") as corpus_dir:
        materialized = []
        for dump, expected in cases:
            filename = secrets.token_hex(16) + ".txt"
            filepath = os.path.join(corpus_dir, filename)
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(dump)
            materialized.append((filepath, expected))

        random.SystemRandom().shuffle(materialized)
        for filepath, expected in materialized:
            actual = run_detector(filepath)
            if actual != expected:
                failures.append((os.path.basename(filepath), expected, actual))

    if failures:
        pytest.fail(f"Detector misclassified {len(failures)} randomized neutral-path dumps: {failures[:10]}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
