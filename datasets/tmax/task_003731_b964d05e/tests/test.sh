#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import string
import subprocess
import pytest

DETECTOR_PATH = "/home/user/detector"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"

def run_detector(payload):
    return subprocess.run(
        [DETECTOR_PATH, payload],
        capture_output=True,
        timeout=5,
    ).returncode

def encode_payload(decoded):
    return base64.b64encode(decoded.encode("utf-8")).decode("ascii")

def random_label(length=14):
    alphabet = string.ascii_lowercase + string.digits
    return "x" + "".join(secrets.choice(alphabet) for _ in range(length))

def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector script is missing: {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector script is not executable: {DETECTOR_PATH}"

def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "No clean files found to test."
    assert len(evil_files) > 0, "No evil files found to test."

    failed_clean = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            payload = f.read().strip()

        result = subprocess.run([DETECTOR_PATH, payload], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(filename)

    failed_evil = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            payload = f.read().strip()

        result = subprocess.run([DETECTOR_PATH, payload], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(filename)

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_clean)}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_evil)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))

def test_generated_unseen_payloads():
    subdomain = random_label()
    path = random_label()
    attacker = random_label()
    token = random_label()

    clean_decoded = [
        f"redirect_url=https://internal-app.local/{path}",
        f"redirect_url=https://{subdomain}.internal-app.local/{path}&token={token}",
        f"redirect_url=https://auth.internal-app.local/{path}/login&token=user",
    ]

    evil_decoded = [
        f"redirect_url=https://{attacker}-internal-app.local/{path}",
        f"redirect_url=https://internal-app.local.{attacker}.com/{path}",
        f"redirect_url=https://{attacker}.com\\@internal-app.local/{path}",
        f"redirect_url=https://{subdomain}.internal-app.local/{path}&token=admin",
    ]

    failures = []
    for decoded in clean_decoded:
        rc = run_detector(encode_payload(decoded))
        if rc != 0:
            failures.append(f"rejected generated clean payload {decoded!r} with status {rc}")

    for decoded in evil_decoded:
        rc = run_detector(encode_payload(decoded))
        if rc != 1:
            failures.append(f"accepted generated malicious payload {decoded!r} with status {rc}")

    if failures:
        pytest.fail(" | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
