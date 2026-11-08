#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/payload_filter.sh"
CLEAN_CORPUS = "/app/corpus/clean/"
EVIL_CORPUS = "/app/corpus/evil/"
KEY = b"9f8e7d6c5b4a3f2e1d"


def run_script(*args):
    return subprocess.run([SCRIPT_PATH, *args], capture_output=True)


def signature(user, nonce):
    return hmac.new(KEY, f"{user}:{nonce}".encode(), hashlib.sha256).hexdigest()


def write_payload(directory, payload):
    path = os.path.join(directory, secrets.token_hex(12) + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    return path


def assert_rejected(result, description):
    assert result.returncode == 1, f"{description} returned {result.returncode}, expected 1"
    assert result.stderr.strip(), f"{description} did not print an error to stderr"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus_evaluation():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing: {CLEAN_CORPUS}"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing: {EVIL_CORPUS}"

    clean_files = sorted(f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f)))
    evil_files = sorted(f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f)))

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    clean_rejected = []
    for filename in clean_files:
        result = run_script(os.path.join(CLEAN_CORPUS, filename))
        if result.returncode != 0:
            clean_rejected.append(filename)

    evil_bypassed = []
    evil_without_error = []
    for filename in evil_files:
        result = run_script(os.path.join(EVIL_CORPUS, filename))
        if result.returncode != 1:
            evil_bypassed.append(filename)
        if not result.stderr.strip():
            evil_without_error.append(filename)

    errors = []
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil did not exit 1: {', '.join(evil_bypassed)}")
    if evil_without_error:
        errors.append(f"{len(evil_without_error)} evil payloads produced no stderr error: {', '.join(evil_without_error)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_payloads_are_actually_validated():
    with tempfile.TemporaryDirectory(prefix="rotation-tests-") as directory:
        user = "acct" + secrets.token_hex(10)
        nonce = secrets.token_hex(18)

        valid = write_payload(directory, {
            "user": user,
            "nonce": nonce,
            "hmac": signature(user, nonce),
        })
        result = run_script(valid)
        assert result.returncode == 0, f"Generated valid payload was rejected: {result.stderr!r}"

        forged = write_payload(directory, {
            "user": user,
            "nonce": nonce,
            "hmac": signature(user, nonce + "x"),
        })
        assert_rejected(run_script(forged), "Generated forged-HMAC payload")

        for metachar in [";", "|", "&", "$", ">", "<", "`"]:
            malicious_user = "acct" + secrets.token_hex(4) + metachar + "payload"
            malicious = write_payload(directory, {
                "user": malicious_user,
                "nonce": nonce,
                "hmac": signature(malicious_user, nonce),
            })
            assert_rejected(run_script(malicious), f"Payload containing {metachar!r}")

        complete = {"user": user, "nonce": nonce, "hmac": signature(user, nonce)}
        for missing in ["user", "nonce", "hmac"]:
            payload = dict(complete)
            del payload[missing]
            path = write_payload(directory, payload)
            assert_rejected(run_script(path), f"Payload missing {missing}")


def test_exactly_one_argument_is_required():
    assert_rejected(run_script(), "Invocation with no arguments")
    with tempfile.TemporaryDirectory(prefix="rotation-args-") as directory:
        user = "argtest" + secrets.token_hex(5)
        nonce = secrets.token_hex(8)
        path = write_payload(directory, {
            "user": user,
            "nonce": nonce,
            "hmac": signature(user, nonce),
        })
        assert_rejected(run_script(path, path), "Invocation with two arguments")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
