#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile
import uuid
import pytest

EXPECTED_KEY = "4a2b9c118f7e6d5c2233445566778899"

CLEAN_DATA = [
    b"SELECT * FROM users WHERE id = 5;",
    b"<div class=\"main\">Welcome to the dashboard</div>",
    b"Error: unexpected token '<' in config.json",
    b"SELECT username, email FROM accounts;"
] * 5

EVIL_DATA = [
    b"SELECT * FROM users WHERE id = 5 UNION SELECT 1, password FROM admin;",
    b"<scr<script>ipt>alert('XSS')</script>",
    b"user_input=1'; DROP TABLE users--",
    b"<img src=x onerror=alert(1)>"
] * 5


def padded(data):
    return data + b" " * ((16 - len(data) % 16) % 16)


def test_recovered_key():
    key_path = "/home/user/recovered_key.txt"
    assert os.path.exists(key_path), f"Recovered key file missing at {key_path}"
    assert os.path.isfile(key_path), f"Recovered key path is not a file: {key_path}"

    with open(key_path, "r") as f:
        key = f.read().strip()

    assert key == EXPECTED_KEY, f"Recovered key is incorrect. Expected {EXPECTED_KEY}, got {key}"


def test_decrypted_corpora():
    expected = {
        "clean": [padded(x) for x in CLEAN_DATA],
        "evil": [padded(x) for x in EVIL_DATA],
    }

    for category, records in expected.items():
        output_dir = f"/home/user/decrypted_corpora/{category}"
        assert os.path.isdir(output_dir), f"Decrypted {category} directory missing at {output_dir}"

        for index, plaintext in enumerate(records):
            output_path = os.path.join(output_dir, f"file_{index}.txt")
            assert os.path.isfile(output_path), f"Missing decrypted file: {output_path}"
            with open(output_path, "rb") as f:
                actual = f.read()
            assert actual == plaintext, f"Incorrect decrypted contents in {output_path}"


def test_classifier_exists():
    script_path = "/home/user/log_classifier.py"
    assert os.path.exists(script_path), f"Classifier script missing at {script_path}"
    assert os.path.isfile(script_path), f"Classifier path is not a regular file: {script_path}"


def test_classifier_accuracy():
    script_path = "/home/user/log_classifier.py"
    assert os.path.exists(script_path), "Classifier script is missing."

    cases = [(padded(data), 1) for data in EVIL_DATA]
    cases += [(padded(data), 0) for data in CLEAN_DATA]
    random.SystemRandom().shuffle(cases)

    failures = []
    case_dir = tempfile.mkdtemp(prefix="scanner_inputs_")
    try:
        for contents, expected_status in cases:
            path = os.path.join(case_dir, uuid.uuid4().hex + ".log")
            with open(path, "wb") as f:
                f.write(contents)

            try:
                result = subprocess.run(
                    ["python3", script_path, path],
                    capture_output=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
                continue

            if result.returncode != expected_status:
                failures.append(
                    f"{os.path.basename(path)} returned {result.returncode}, expected {expected_status}"
                )

        if failures:
            pytest.fail("Classifier failed: " + " | ".join(failures))
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
