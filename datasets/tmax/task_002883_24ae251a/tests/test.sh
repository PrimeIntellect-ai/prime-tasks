#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.py"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CLEAN_CORPUS_DIR = "/app/corpora/clean"


def run_detector(filepath):
    """Runs the detector script on the given file and returns its output lines."""
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, filepath],
        capture_output=True,
        text=True
    )
    return result.stdout.strip().splitlines()


def test_detector_exists():
    """Ensure the student has created the detector script at the expected location."""
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"


def test_evil_corpus_rejection():
    """Assert that every line in the supplied evil corpus is flagged EVIL."""
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)
                  if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert evil_files, "No files found in evil corpus directory."

    bypassed_files = []
    total_evil_files = len(evil_files)

    for filepath in evil_files:
        with open(filepath, 'r') as f:
            expected_lines = sum(1 for _ in f)

        output_lines = run_detector(filepath)

        if len(output_lines) != expected_lines:
            bypassed_files.append(os.path.basename(filepath))
            continue

        misclassified = sum(1 for out in output_lines if out.strip() != "EVIL")
        if misclassified > 0:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {total_evil_files} evil bypassed. "
                    f"Offending files: {', '.join(bypassed_files)}")


def test_clean_corpus_preservation():
    """Assert that every line in the supplied clean corpus is flagged CLEAN."""
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)
                   if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert clean_files, "No files found in clean corpus directory."

    modified_files = []
    total_clean_files = len(clean_files)

    for filepath in clean_files:
        with open(filepath, 'r') as f:
            expected_lines = sum(1 for _ in f)

        output_lines = run_detector(filepath)

        if len(output_lines) != expected_lines:
            modified_files.append(os.path.basename(filepath))
            continue

        misclassified = sum(1 for out in output_lines if out.strip() != "CLEAN")
        if misclassified > 0:
            modified_files.append(os.path.basename(filepath))

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {total_clean_files} clean modified. "
                    f"Offending files: {', '.join(modified_files)}")


def obfuscate(payload):
    return "ATTK_" + "".join(f"{ord(ch) ^ 0x37:02x}" for ch in payload[::-1])


def test_randomized_mixed_corpus():
    """Exercise clean and obfuscated lines together at an unpredictable neutral path."""
    rng = secrets.SystemRandom()
    cases = []

    attack_templates = [
        "1' OR '1'='1' -- {}",
        "1 UNION SELECT username,password FROM users -- {}",
        "admin' OR 1=1--{}",
        "<script>alert('{}')</script>",
        "\"><img src=x onerror=alert('{}')>",
        "; DROP TABLE audit_log; -- {}",
    ]
    keys = ["id", "search", "page", "user", "action", "filter"]

    for i in range(24):
        marker = secrets.token_hex(6)
        payload = attack_templates[i % len(attack_templates)].format(marker)
        cases.append((f"{rng.choice(keys)}={obfuscate(payload)}", "EVIL"))

    benign_values = [
        "apples", "about", "login", "blue-widget", "quarterly-report",
        "john.doe", "page-42", "sort-ascending", "help-center", "active-users"
    ]
    for i in range(26):
        value = f"{rng.choice(benign_values)}-{secrets.token_hex(5)}"
        cases.append((f"{rng.choice(keys)}={value}", "CLEAN"))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="query-check-") as tempdir:
        corpus = os.path.join(tempdir, secrets.token_hex(10) + ".txt")
        with open(corpus, "w", encoding="utf-8") as f:
            for line, _ in cases:
                f.write(line + "\n")

        result = subprocess.run(
            ["python3", DETECTOR_SCRIPT, corpus],
            capture_output=True,
            text=True,
            timeout=20
        )

    assert result.returncode == 0, f"Detector exited with status {result.returncode}: {result.stderr}"
    expected = [label for _, label in cases]
    actual = result.stdout.splitlines()
    assert actual == expected, "Detector misclassified the randomized mixed corpus or emitted extra output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
