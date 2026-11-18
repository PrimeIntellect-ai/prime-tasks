#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import base64
import json
import os
import random
import secrets
import subprocess
import tempfile
import uuid
import pytest

AGENT_SCRIPT = "/home/user/detector.py"
CLEAN_CORPUS = "/app/corpus/clean/tokens.txt"
EVIL_CORPUS = "/app/corpus/evil/tokens.txt"
REDACTION = "[MALICIOUS_TOKEN_REDACTED]"

def run_detector(input_file, output_file):
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    result = subprocess.run(
        ["python3", AGENT_SCRIPT, input_file, output_file],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Script failed with return code {result.returncode}\nstderr: {result.stderr}"
    assert os.path.exists(output_file), f"Output file not created at {output_file}"

def test_clean_corpus():
    with tempfile.NamedTemporaryFile(delete=False) as tmp_out:
        out_path = tmp_out.name

    try:
        run_detector(CLEAN_CORPUS, out_path)

        with open(CLEAN_CORPUS, "r") as f:
            clean_tokens = f.read().splitlines()
        with open(out_path, "r") as f:
            out_tokens = f.read().splitlines()

        assert len(clean_tokens) == len(out_tokens), f"Expected {len(clean_tokens)} output lines, got {len(out_tokens)}"

        modified_count = 0
        for i, (expected, actual) in enumerate(zip(clean_tokens, out_tokens)):
            if expected != actual:
                modified_count += 1

        assert modified_count == 0, f"{modified_count} of {len(clean_tokens)} clean tokens modified."
    finally:
        if os.path.exists(out_path):
            os.remove(out_path)

def test_evil_corpus():
    with tempfile.NamedTemporaryFile(delete=False) as tmp_out:
        out_path = tmp_out.name

    try:
        run_detector(EVIL_CORPUS, out_path)

        with open(EVIL_CORPUS, "r") as f:
            evil_tokens = f.read().splitlines()
        with open(out_path, "r") as f:
            out_tokens = f.read().splitlines()

        assert len(evil_tokens) == len(out_tokens), f"Expected {len(evil_tokens)} output lines, got {len(out_tokens)}"

        bypassed_count = 0
        for i, actual in enumerate(out_tokens):
            if actual != REDACTION:
                bypassed_count += 1

        assert bypassed_count == 0, f"{bypassed_count} of {len(evil_tokens)} evil tokens bypassed redaction."
    finally:
        if os.path.exists(out_path):
            os.remove(out_path)

def encode_json(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).decode()

def test_randomized_mixed_corpus():
    cases = []
    bypass_algs = ["none", "NONE", "debug"]

    # Give clean and malicious tokens the same payload and signature shapes so
    # classification must be based on the decoded algorithm header.
    for i in range(18):
        payload = {
            "user": f"subject-{secrets.token_hex(8)}",
            "admin": bool(i % 2),
            "nonce": secrets.token_hex(12),
        }
        signature = f"sig-{secrets.token_urlsafe(18)}"

        clean = f'{encode_json({"alg": "HS256"})}.{encode_json(payload)}.{signature}'
        cases.append((clean, clean))

        malicious_alg = bypass_algs[i % len(bypass_algs)]
        malicious = f'{encode_json({"alg": malicious_alg})}.{encode_json(payload)}.{signature}'
        cases.append((malicious, REDACTION))

    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory() as tmp_dir:
        input_path = os.path.join(tmp_dir, f"collected-{uuid.uuid4().hex}.log")
        output_path = os.path.join(tmp_dir, f"sanitized-{uuid.uuid4().hex}.log")

        with open(input_path, "w") as f:
            f.write("\n".join(token for token, _ in cases))

        run_detector(input_path, output_path)

        with open(output_path, "r") as f:
            actual = f.read().splitlines()

        expected = [result for _, result in cases]
        assert len(actual) == len(expected), f"Expected {len(expected)} output lines, got {len(actual)}"
        assert actual == expected, "Randomized mixed clean/malicious corpus was classified incorrectly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
