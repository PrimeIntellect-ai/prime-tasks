#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import base64
import hashlib
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/detector/target/release/detector"
EVIL_CORPUS = "/app/evaluation_corpus/evil"
CLEAN_CORPUS = "/app/evaluation_corpus/clean"
CERTIFICATE = "/app/rogue_cert.pem"

def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did you compile in release mode?"
    assert os.path.isfile(EXECUTABLE), f"Expected {EXECUTABLE} to be a file."
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."

def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing at {EVIL_CORPUS}"
    evil_files = sorted([f for f in os.listdir(EVIL_CORPUS) if f.endswith('.json')])
    assert len(evil_files) > 0, "No evil files found in corpus."

    bypassed = []
    for f in evil_files:
        filepath = os.path.join(EVIL_CORPUS, f)
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)

        # Criteria: exit code 1 and stdout contains EVIL
        if result.returncode != 1 or "EVIL" not in result.stdout:
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending file basenames: {', '.join(bypassed)}")

def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing at {CLEAN_CORPUS}"
    clean_files = sorted([f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.json')])
    assert len(clean_files) > 0, "No clean files found in corpus."

    modified = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_CORPUS, f)
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)

        # Criteria: exit code 0 and stdout contains CLEAN
        if result.returncode != 0 or "CLEAN" not in result.stdout:
            modified.append(f)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified. Offending file basenames: {', '.join(modified)}")

def _fingerprint():
    der = subprocess.check_output([
        "openssl", "x509", "-in", CERTIFICATE, "-outform", "DER"
    ])
    return hashlib.sha256(der).hexdigest()

def _encode_payload(text):
    raw = text.encode("utf-8")
    return base64.b64encode(bytes(b ^ 0x5A for b in raw)).decode("ascii")

def test_generated_path_neutral_cases():
    fingerprint = _fingerprint()
    root = tempfile.mkdtemp(prefix="detector-verifier-")
    input_dir = os.path.join(root, "inputs")
    os.mkdir(input_dir)
    cases = []

    try:
        for i in range(12):
            prefix = secrets.token_hex(5)
            suffix = secrets.token_hex(7)
            evil_text = f"{prefix} EXEC_C2: {fingerprint} {suffix}"

            if i % 2 == 0:
                clean_text = f"{prefix} EXEC_CX: {fingerprint} {suffix}"
            else:
                replacement = "0" if fingerprint[0] != "0" else "1"
                wrong_fingerprint = replacement + fingerprint[1:]
                clean_text = f"{prefix} EXEC_C2: {wrong_fingerprint} {suffix}"

            for expected, plaintext in [("EVIL", evil_text), ("CLEAN", clean_text)]:
                filename = secrets.token_hex(16) + ".json"
                filepath = os.path.join(input_dir, filename)
                document = {
                    "timestamp": "2023-10-25T12:00:00Z",
                    "metadata": {"source_ip": f"10.{i}.20.30"},
                    "data_payload": _encode_payload(plaintext),
                }
                with open(filepath, "w", encoding="utf-8") as handle:
                    json.dump(document, handle)
                cases.append((filepath, expected))

        random.SystemRandom().shuffle(cases)
        failures = []
        for filepath, expected in cases:
            result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)
            expected_code = 1 if expected == "EVIL" else 0
            if result.returncode != expected_code or expected not in result.stdout:
                failures.append(
                    f"{os.path.basename(filepath)} expected {expected}/{expected_code}, "
                    f"got code {result.returncode} and stdout {result.stdout!r}"
                )

        if failures:
            pytest.fail("Generated cases failed:\n" + "\n".join(failures))
    finally:
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
