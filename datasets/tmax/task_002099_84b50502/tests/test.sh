#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import base64
import os
import random
import secrets
import string
import subprocess
import tempfile
import uuid
import pytest

AGENT_SCRIPT = "/home/user/filter.py"
EVIL_CORPUS_DIR = "/app/eval_corpus/evil"
CLEAN_CORPUS_DIR = "/app/eval_corpus/clean"
KEY = "Sup3rS3cr3tX0R"


def run_agent_script(input_path, output_path):
    cmd = ["python3", AGENT_SCRIPT, "--input", input_path, "--output", output_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result


def encrypt(data):
    key_bytes = KEY.encode()
    xored = bytes(value ^ key_bytes[index % len(key_bytes)] for index, value in enumerate(data))
    return base64.b64encode(xored)


def random_text(min_length=0, max_length=40):
    alphabet = string.ascii_letters + string.digits + " _-./:=,"
    length = secrets.randbelow(max_length - min_length + 1) + min_length
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_adversarial_corpus():
    if not os.path.isfile(AGENT_SCRIPT):
        pytest.fail(f"Cannot test corpus: {AGENT_SCRIPT} is missing.")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    evil_bypassed = []
    clean_modified = []

    with tempfile.TemporaryDirectory() as tmpdir:
        # Test evil corpus
        for filename in evil_files:
            input_path = os.path.join(EVIL_CORPUS_DIR, filename)
            output_path = os.path.join(tmpdir, f"evil_out_{filename}")

            result = run_agent_script(input_path, output_path)

            if result.returncode != 1 or os.path.exists(output_path):
                evil_bypassed.append(filename)

        # Test clean corpus
        for filename in clean_files:
            input_path = os.path.join(CLEAN_CORPUS_DIR, filename)
            output_path = os.path.join(tmpdir, f"clean_out_{filename}")

            result = run_agent_script(input_path, output_path)

            if result.returncode != 0 or not os.path.exists(output_path):
                clean_modified.append(filename)
            else:
                with open(input_path, "rb") as f_in, open(output_path, "rb") as f_out:
                    if f_in.read() != f_out.read():
                        clean_modified.append(filename)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_randomized_payloads_at_neutral_paths():
    if not os.path.isfile(AGENT_SCRIPT):
        pytest.fail(f"Cannot test randomized payloads: {AGENT_SCRIPT} is missing.")

    cases = []

    # Generate fresh payloads whose classifications are derived from plaintext.
    for index in range(24):
        marker = "EXFILTRATE" if index % 2 == 0 else "C2_EXEC"
        plaintext = (random_text() + marker + random_text()).encode("ascii")
        cases.append(plaintext)

    clean_fragments = [
        "EXFILTRAT", "EXFILTRATEd", "exfiltrate", "C2_EXE", "C2-EXEC",
        "heartbeat", "status=OK", "ordinary request", "C2_exec", "EX FILTRATE"
    ]
    for index in range(24):
        plaintext = (random_text() + clean_fragments[index % len(clean_fragments)] + random_text()).encode("ascii")
        assert b"EXFILTRATE" not in plaintext and b"C2_EXEC" not in plaintext
        cases.append(plaintext)

    random.SystemRandom().shuffle(cases)
    failures = []

    with tempfile.TemporaryDirectory(prefix="payload-check-") as tmpdir:
        for plaintext in cases:
            encrypted = encrypt(plaintext)
            expected_evil = b"EXFILTRATE" in plaintext or b"C2_EXEC" in plaintext
            input_path = os.path.join(tmpdir, uuid.uuid4().hex)
            output_path = os.path.join(tmpdir, uuid.uuid4().hex)

            with open(input_path, "wb") as handle:
                handle.write(encrypted)

            result = run_agent_script(input_path, output_path)

            if expected_evil:
                if result.returncode != 1 or os.path.exists(output_path):
                    failures.append("fresh malicious payload was not rejected")
            else:
                if result.returncode != 0 or not os.path.isfile(output_path):
                    failures.append("fresh clean payload was not preserved")
                else:
                    with open(output_path, "rb") as handle:
                        if handle.read() != encrypted:
                            failures.append("fresh clean payload was modified")

    if failures:
        pytest.fail(f"{len(failures)} randomized classification failures: " + "; ".join(failures[:5]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
