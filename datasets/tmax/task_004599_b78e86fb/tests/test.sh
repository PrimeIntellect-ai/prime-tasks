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
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"

def test_detector_exists_and_executable():
    """Verify that the detector script exists and is executable."""
    assert os.path.isfile(DETECTOR_PATH), f"Detector script not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector script at {DETECTOR_PATH} is not executable"

def test_evil_corpus_rejected():
    """Verify that all files in the evil corpus are rejected (exit code 1)."""
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"

    bypassed = []
    for filename in evil_files:
        file_path = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_PATH, file_path], capture_output=True)
        if result.returncode != 1:
            bypassed.append(filename)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed (did not exit with code 1). Offending files: {', '.join(bypassed)}")

def test_clean_corpus_accepted():
    """Verify that all files in the clean corpus are accepted (exit code 0)."""
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    rejected = []
    for filename in clean_files:
        file_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_PATH, file_path], capture_output=True)
        if result.returncode != 0:
            rejected.append(filename)

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(clean_files)} clean modified/rejected (did not exit with code 0). Offending files: {', '.join(rejected)}")

def test_generated_hidden_corpus_is_classified_by_contents():
    """Exercise a mixed corpus at unpredictable paths with expected results derived here."""
    cases = []
    for kind in ("evil", "prefix_only", "header_only", "neither"):
        for _ in range(16):
            suffix = secrets.token_hex(8)
            command = f"echo-{secrets.token_hex(6)}"
            if kind in ("evil", "prefix_only"):
                session = "D00B" + suffix
            else:
                session = "ABCD" + suffix

            lines = [
                "GET /api.php HTTP/1.1",
                f"Host: host-{secrets.token_hex(4)}.invalid",
                f"Cookie: session={session}",
                f"User-Agent: audit-{secrets.token_hex(4)}",
            ]
            if kind in ("evil", "header_only"):
                lines.append(f"X-System-Cmd: {command}")
            request = "\r\n".join(lines) + "\r\n\r\n"
            cases.append((request, 1 if kind == "evil" else 0))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="request_checks_") as corpus_dir:
        for request, expected in cases:
            filename = secrets.token_hex(16) + ".dat"
            path = os.path.join(corpus_dir, filename)
            with open(path, "wb") as request_file:
                request_file.write(request.encode("ascii"))
            try:
                result = subprocess.run(
                    [DETECTOR_PATH, path], capture_output=True, timeout=10
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"
            if actual != expected:
                failures.append((filename, expected, actual))

    assert not failures, (
        f"Detector misclassified {len(failures)} generated hidden requests; "
        f"examples: {failures[:5]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
