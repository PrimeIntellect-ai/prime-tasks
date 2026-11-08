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

DETECTOR_SCRIPT = "/home/user/detector.py"
CLEAN_CORPUS_DIR = "/app/test_clean"
EVIL_CORPUS_DIR = "/app/test_evil"

def test_detector_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"

def run_detector(filepath):
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, filepath],
        capture_output=True,
        text=True,
        timeout=10
    )
    return result.stdout.strip()

def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.txt')]
    assert len(clean_files) > 0, "No clean files found to test."

    failures = []
    for filepath in clean_files:
        output = run_detector(filepath)
        if output != "CLEAN":
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files modified/rejected (expected CLEAN). Offending files: {failures}")

def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.txt')]
    assert len(evil_files) > 0, "No evil files found to test."

    failures = []
    for filepath in evil_files:
        output = run_detector(filepath)
        if output != "EVIL":
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed (expected EVIL). Offending files: {failures}")

def test_fresh_corpus_at_opaque_paths():
    clean_subjects = [
        "Rigorous statistical analysis",
        "Clear data visualization",
        "Careful machine learning evaluation",
        "A reproducible data science experiment",
    ]
    clean_predicates = [
        "reveals important feature distributions in the dataset",
        "measures model accuracy on an independent holdout set",
        "uses hypothesis testing to validate the observed results",
        "compares predictive models with well-defined metrics",
    ]
    evil_subjects = [
        "A limited-time online coupon",
        "My favorite pepperoni pizza",
        "The warm and sunny weekend weather",
        "An unbelievable free vacation prize",
    ]
    evil_predicates = [
        "is available if you click the advertisement right now",
        "was delicious during dinner with my friends",
        "made the afternoon perfect for a walk in the park",
        "can be claimed by buying cheap products today",
    ]

    cases = []
    for _ in range(10):
        cases.append((f"{secrets.choice(clean_subjects)} {secrets.choice(clean_predicates)}.", "CLEAN"))
        cases.append((f"{secrets.choice(evil_subjects)} {secrets.choice(evil_predicates)}.", "EVIL"))
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="detector_eval_") as corpus_dir:
        files = []
        for text, expected in cases:
            path = os.path.join(corpus_dir, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            files.append((path, expected))

        random.SystemRandom().shuffle(files)
        for path, expected in files:
            output = run_detector(path)
            if output != expected:
                failures.append((os.path.basename(path), expected, output))

    if failures:
        pytest.fail(f"Detector failed fresh semantic cases at opaque paths: {failures}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
