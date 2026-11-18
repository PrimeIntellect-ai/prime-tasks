#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest

CLASSIFIER_PATH = "/home/user/classifier"
EVIL_CORPUS_DIR = "/home/user/evidence/evil/"
CLEAN_CORPUS_DIR = "/home/user/evidence/clean/"
KEY = b"\x13\x37\xBE\xEF"

def run_classifier(path):
    return subprocess.run([CLASSIFIER_PATH, path], capture_output=True, timeout=10)

def test_classifier_exists_and_executable():
    assert os.path.exists(CLASSIFIER_PATH), f"Classifier binary not found at {CLASSIFIER_PATH}"
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier path {CLASSIFIER_PATH} is not a file"
    assert os.access(CLASSIFIER_PATH, os.X_OK), f"Classifier binary at {CLASSIFIER_PATH} is not executable"

def test_classifier_against_adversarial_corpus():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, f"No files found in evil corpus directory {EVIL_CORPUS_DIR}"
    assert len(clean_files) > 0, f"No files found in clean corpus directory {CLEAN_CORPUS_DIR}"

    evil_bypassed = []
    for evil_file in evil_files:
        result = run_classifier(evil_file)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = run_classifier(clean_file)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:10])}{'...' if len(evil_bypassed) > 10 else ''}")

    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified[:10])}{'...' if len(clean_modified) > 10 else ''}")

    assert not error_messages, " | ".join(error_messages)

def test_classifier_on_unseen_neutral_paths_and_decoy_macs():
    cases = []
    with tempfile.TemporaryDirectory(prefix="inspection-") as case_dir:
        for i in range(160):
            ip = f"{secrets.randbelow(223) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}"
            sni = f"{secrets.token_hex(8)}.{secrets.choice(['com', 'net', 'org', 'io'])}"
            base = {
                "client_ip": ip,
                "tls_sni": sni,
                "csp_report": {"document-uri": f"https://{secrets.token_hex(6)}.example/report"},
                "request_id": secrets.token_hex(12),
            }

            evil = dict(base)
            message = f"{ip}|{sni}".encode()
            evil["x_c2_mac"] = hmac.new(KEY, message, hashlib.sha256).hexdigest()
            cases.append((evil, 1))

            clean = dict(base)
            if i % 2 == 0:
                clean["x_c2_mac"] = secrets.token_hex(32)
                while hmac.compare_digest(clean["x_c2_mac"], evil["x_c2_mac"]):
                    clean["x_c2_mac"] = secrets.token_hex(32)
            cases.append((clean, 0))

        random.SystemRandom().shuffle(cases)
        failures = []
        for payload, expected in cases:
            path = os.path.join(case_dir, secrets.token_hex(16))
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f, separators=(",", ":"), sort_keys=bool(secrets.randbits(1)))
            result = run_classifier(path)
            if result.returncode != expected:
                failures.append((os.path.basename(path), expected, result.returncode))

        assert not failures, f"Classifier failed {len(failures)} unseen cases; first failures: {failures[:10]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
