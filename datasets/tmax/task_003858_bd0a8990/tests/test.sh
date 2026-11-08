#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import uuid

DETECTOR_SCRIPT = "/home/user/detector.py"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EXPECTED_PREFIX = "X_BYPASS"


def run_detector(payload_path):
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, payload_path],
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result.stdout.strip()


def test_detector_script_exists():
    """Ensure the detector script was created."""
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"


def test_adversarial_corpus():
    """Retain the original checks against the supplied corpus."""
    assert os.path.isfile(DETECTOR_SCRIPT), "Detector script is missing."

    evil_files = []
    if os.path.isdir(EVIL_CORPUS_DIR):
        evil_files = [
            os.path.join(EVIL_CORPUS_DIR, f)
            for f in os.listdir(EVIL_CORPUS_DIR)
            if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))
        ]

    clean_files = []
    if os.path.isdir(CLEAN_CORPUS_DIR):
        clean_files = [
            os.path.join(CLEAN_CORPUS_DIR, f)
            for f in os.listdir(CLEAN_CORPUS_DIR)
            if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
        ]

    assert len(evil_files) > 0, "Evil corpus is empty or missing."
    assert len(clean_files) > 0, "Clean corpus is empty or missing."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        try:
            output = run_detector(evil_file)
            if output != "EVIL":
                evil_bypassed.append((os.path.basename(evil_file), output))
        except Exception as exc:
            evil_bypassed.append((os.path.basename(evil_file), f"Error: {exc}"))

    for clean_file in clean_files:
        try:
            output = run_detector(clean_file)
            if output != "CLEAN":
                clean_modified.append((os.path.basename(clean_file), output))
        except Exception as exc:
            clean_modified.append((os.path.basename(clean_file), f"Error: {exc}"))

    error_messages = []
    if evil_bypassed:
        error_messages.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: "
            + ", ".join(item[0] for item in evil_bypassed)
        )
    if clean_modified:
        error_messages.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected). Offending files: "
            + ", ".join(item[0] for item in clean_modified)
        )

    assert not evil_bypassed and not clean_modified, " | ".join(error_messages)


def test_generated_hidden_payloads():
    """Exercise the detector through unpredictable paths and payload values."""
    assert os.path.isfile(DETECTOR_SCRIPT), "Detector script is missing."

    token = uuid.uuid4().hex
    cases = [
        (f"../{token}.txt", "EVIL"),
        (f"uploads/../../{token}", "EVIL"),
        (f"images/..%2f..%2f{token}", "EVIL"),
        (f"images/..%2F{token}", "EVIL"),
        (f"images/%2e%2e%2f{token}", "EVIL"),
        (f"images/%2E%2e%2F{token}", "EVIL"),
        (f"/var/tmp/{token}", "EVIL"),
        (f"photo_{token}.png%00.php", "EVIL"),
        (f"photo_{token}.png\x00.php", "EVIL"),
        (f"{EXPECTED_PREFIX}_{token}.exe", "EVIL"),
        (EXPECTED_PREFIX, "EVIL"),
        (f"avatar_{token}.jpg", "CLEAN"),
        (f"documents/{token}_report.pdf", "CLEAN"),
        (f"archive_{token}.tar.gz", "CLEAN"),
        (f"scripts/{token}.js", "CLEAN"),
        (f"nested/{token}/image.png", "CLEAN"),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="detector-hidden-") as payload_dir:
        for payload, expected in cases:
            payload_path = os.path.join(payload_dir, uuid.uuid4().hex + ".dat")
            with open(payload_path, "wb") as handle:
                handle.write(payload.encode("utf-8"))
            try:
                output = run_detector(payload_path)
            except Exception as exc:
                failures.append(f"expected {expected}, error: {exc}")
                continue
            if output != expected:
                failures.append(f"expected {expected}, got {output!r}")

    assert not failures, "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
