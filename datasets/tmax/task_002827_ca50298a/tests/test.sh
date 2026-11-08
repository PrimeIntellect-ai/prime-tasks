#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest


def test_engine_secret_recovered():
    secret_path = "/home/user/.engine_secret"
    assert os.path.exists(secret_path), f"Missing secret file: {secret_path}"
    with open(secret_path, "r") as f:
        content = f.read().strip()
    assert content == "a9f3b2c1", f"Incorrect secret content. Expected 'a9f3b2c1', got '{content}'"


def test_filter_script_exists():
    filter_path = "/home/user/filter.py"
    assert os.path.isfile(filter_path), f"Filter script not found at {filter_path}"


def test_adversarial_corpus_evil():
    evil_dir = "/app/corpora/evil"
    filter_path = "/home/user/filter.py"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.bin')]
    assert len(evil_files) > 0, "No evil files found in corpus"

    bypassed = []
    for fpath in evil_files:
        result = subprocess.run(
            ["python3", filter_path, fpath],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 1 or stdout != "EVIL":
            bypassed.append(os.path.basename(fpath))

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}")


def test_adversarial_corpus_clean():
    clean_dir = "/app/corpora/clean"
    filter_path = "/home/user/filter.py"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.bin')]
    assert len(clean_files) > 0, "No clean files found in corpus"

    modified = []
    for fpath in clean_files:
        result = subprocess.run(
            ["python3", filter_path, fpath],
            capture_output=True,
            text=True
        )
        stdout = result.stdout.strip()
        if result.returncode != 0 or stdout != "CLEAN":
            modified.append(os.path.basename(fpath))

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(modified)}")


def test_classifier_on_runtime_generated_mixed_corpus():
    filter_path = "/home/user/filter.py"
    alphabet = string.ascii_letters + string.digits

    # Generate equal-length clean and malicious payloads at verification time. Both
    # classes share one neutrally named directory, and filenames reveal no label.
    cases = []
    for expected, prefix in [("CLEAN", "DAT:")] * 25 + [("EVIL", "CMD:")] * 25:
        suffix = ''.join(secrets.choice(alphabet) for _ in range(40))
        decoded = (prefix + suffix).encode("ascii")
        encoded = bytes(byte ^ 0x42 for byte in decoded)
        cases.append((expected, encoded))
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="payloads_") as corpus_dir:
        generated = []
        for expected, payload in cases:
            filename = secrets.token_hex(16) + ".bin"
            path = os.path.join(corpus_dir, filename)
            with open(path, "wb") as f:
                f.write(payload)
            generated.append((expected, path))

        random.SystemRandom().shuffle(generated)
        for expected, path in generated:
            result = subprocess.run(
                ["python3", filter_path, path],
                capture_output=True,
                text=True,
                timeout=10
            )
            wanted_code = 1 if expected == "EVIL" else 0
            if result.returncode != wanted_code or result.stdout.strip() != expected:
                failures.append(os.path.basename(path))

    if failures:
        pytest.fail(f"Classifier failed {len(failures)} runtime-generated mixed-corpus cases")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
