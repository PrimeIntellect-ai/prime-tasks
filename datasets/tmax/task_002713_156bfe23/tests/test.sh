#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import jwt
import pytest

SCRIPT_PATH = "/home/user/policy_validator.py"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
HEADER = "X-Corp-Sec-Auth"
SECRET = "zulu-delta-niner-42"


def run_validator(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_policy_validator_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_policy_validator_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory missing at {CLEAN_CORPUS}"
    clean_files = sorted([f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.json')])
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_CORPUS, f)
        result = run_validator(filepath)
        output = result.stdout.strip()
        if output != "ALLOW" or result.returncode != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (blocked or failed). Offending files: {', '.join(failed_files)}")


def test_policy_validator_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory missing at {EVIL_CORPUS}"
    evil_files = sorted([f for f in os.listdir(EVIL_CORPUS) if f.endswith('.json')])
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for f in evil_files:
        filepath = os.path.join(EVIL_CORPUS, f)
        result = run_validator(filepath)
        output = result.stdout.strip()
        if output != "BLOCK" or result.returncode != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}")


def test_policy_validator_generated_requests():
    nonce = secrets.token_hex(16)
    valid_token = jwt.encode(
        {"role": "uploader", "nonce": nonce}, SECRET, algorithm="HS256"
    )
    bad_signature_token = jwt.encode(
        {"role": "uploader", "nonce": nonce},
        secrets.token_hex(24),
        algorithm="HS256",
    )
    wrong_role_token = jwt.encode(
        {"role": "viewer", "nonce": nonce}, SECRET, algorithm="HS256"
    )
    wrong_algorithm_token = jwt.encode(
        {"role": "uploader", "nonce": nonce}, SECRET, algorithm="HS384"
    )

    base = {
        "headers": {HEADER: f"Bearer {valid_token}"},
        "upload_filename": f"document-{nonce}.pdf",
        "upload_path": f"/srv/uploads/{nonce}/",
    }

    cases = []

    def add(expected, mutate=None):
        request = copy.deepcopy(base)
        if mutate is not None:
            mutate(request)
        cases.append((request, expected))

    add("ALLOW")
    add("ALLOW", lambda r: r["headers"].update({"User-Agent": "generated-test"}))
    add("BLOCK", lambda r: r["headers"].update({HEADER: f"Bearer {bad_signature_token}"}))
    add("BLOCK", lambda r: r["headers"].update({HEADER: f"Bearer {wrong_role_token}"}))
    add("BLOCK", lambda r: r["headers"].update({HEADER: f"Bearer {wrong_algorithm_token}"}))
    add("BLOCK", lambda r: r["headers"].update({HEADER: "Bearer not-a-jwt"}))
    add("BLOCK", lambda r: r["headers"].pop(HEADER))
    add("BLOCK", lambda r: r.update({"upload_path": f"/srv/uploads/{nonce}/../private/"}))
    add("BLOCK", lambda r: r.update({"upload_path": f"/srv/uploads/{nonce}/%2E%2e%2Fprivate/"}))
    add("BLOCK", lambda r: r.update({"upload_filename": f"note-{nonce}<ScRiPt>alert(1)</sCrIpT>.txt"}))
    add("BLOCK", lambda r: r.update({"upload_filename": f"photo-{nonce}.jpg ONLoAd=run()"}))

    random.SystemRandom().shuffle(cases)
    temp_dir = tempfile.mkdtemp(prefix="policy-cases-")
    failures = []
    try:
        for request, expected in cases:
            filepath = os.path.join(temp_dir, secrets.token_hex(16) + ".json")
            with open(filepath, "w", encoding="utf-8") as handle:
                json.dump(request, handle)

            result = run_validator(filepath)
            actual = result.stdout.strip()
            if result.returncode != 0 or actual != expected:
                failures.append(
                    f"expected {expected}, got {actual!r}, exit={result.returncode}"
                )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    if failures:
        pytest.fail("Generated request checks failed: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
