#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import string
import subprocess
import pytest

BINARY_PATH = "/home/user/redactor"


def compute_expected(line: str) -> str:
    # Remove trailing newline for processing
    content = line.rstrip('\n')

    # Redact private keys
    content = re.sub(
        r'-----BEGIN PRIVATE KEY-----.*?-----END PRIVATE KEY-----',
        '[REDACTED_KEY]',
        content,
    )

    # Redact XSS payloads
    content = re.sub(
        r'<script>.*?</script>',
        '[MALICIOUS_PAYLOAD]',
        content,
    )

    # Compute SHA-256 hash
    h = hashlib.sha256(content.encode('utf-8')).hexdigest()

    # Return formatted string with newline
    return f"{content} | SHA256: {h}\n"


def run_redactor(input_data: str) -> str:
    if not os.path.isfile(BINARY_PATH):
        pytest.fail(f"Binary {BINARY_PATH} does not exist.")
    if not os.access(BINARY_PATH, os.X_OK):
        pytest.fail(f"Binary {BINARY_PATH} is not executable.")

    try:
        result = subprocess.run(
            [BINARY_PATH],
            input=input_data.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
        )
        if result.returncode != 0:
            pytest.fail(
                f"Execution of {BINARY_PATH} returned {result.returncode}: "
                f"{result.stderr.decode('utf-8', errors='replace')}"
            )
        return result.stdout.decode('utf-8')
    except Exception as e:
        pytest.fail(f"Execution of {BINARY_PATH} failed: {e}")


def test_clean_corpus():
    clean_dir = "/app/corpora/clean"
    if not os.path.isdir(clean_dir):
        pytest.fail(f"Clean corpus directory {clean_dir} does not exist.")

    files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    if not files:
        pytest.fail(f"No files found in {clean_dir}.")

    failed_files = []

    for filename in files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            input_data = f.read()

        expected_output = compute_expected(input_data)
        actual_output = run_redactor(input_data)

        if actual_output != expected_output:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(files)} clean modified. "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_evil_corpus():
    evil_dir = "/app/corpora/evil"
    if not os.path.isdir(evil_dir):
        pytest.fail(f"Evil corpus directory {evil_dir} does not exist.")

    files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    if not files:
        pytest.fail(f"No files found in {evil_dir}.")

    failed_files = []

    for filename in files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            input_data = f.read()

        expected_output = compute_expected(input_data)
        actual_output = run_redactor(input_data)

        if actual_output != expected_output:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(files)} evil bypassed. "
            f"Offending files: {', '.join(failed_files)}"
        )


def random_text(min_len=8, max_len=40):
    alphabet = string.ascii_letters + string.digits + " /?&=._:;!@#$%^*()+,[]{}"
    length = min_len + secrets.randbelow(max_len - min_len + 1)
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def assert_case(input_data: str):
    expected = compute_expected(input_data)
    actual = run_redactor(input_data)
    assert actual == expected, (
        f"Incorrect output for generated input {input_data!r}\n"
        f"Expected: {expected!r}\nActual: {actual!r}"
    )


def test_generated_unseen_inputs():
    # Generate fresh inputs at verification time so corpus-specific lookup tables
    # cannot satisfy the required general redaction and hashing behavior.
    cases = []
    for _ in range(16):
        nonce = secrets.token_hex(16)
        cases.append(f"GET /generated/{nonce}?value={random_text()} HTTP/1.1\n")

        key_body = secrets.token_urlsafe(24) + random_text()
        cases.append(
            f"{random_text()}-----BEGIN PRIVATE KEY-----{key_body}"
            f"-----END PRIVATE KEY-----{random_text()}\n"
        )

        payload = f"do_{secrets.token_hex(12)}({random_text()})"
        cases.append(
            f"GET /q?nonce={nonce}&x=<script>{payload}</script> HTTP/1.1\n"
        )

        cases.append(
            f"{random_text()}<script>{secrets.token_hex(8)}</script>"
            f"{random_text()}-----BEGIN PRIVATE KEY-----{secrets.token_hex(20)}"
            f"-----END PRIVATE KEY-----{random_text()}\n"
        )

    # Exercise repeated matches, adjacency, redaction ordering, near-misses, and
    # an input without a trailing newline.
    token = secrets.token_hex(20)
    cases.extend([
        f"<script>{token}a</script>middle<script>{token}b</script>\n",
        f"-----BEGIN PRIVATE KEY-----{token}a-----END PRIVATE KEY-----"
        f"-----BEGIN PRIVATE KEY-----{token}b-----END PRIVATE KEY-----\n",
        f"pre-----BEGIN PRIVATE KEY-----<script>{token}</script>"
        f"-----END PRIVATE KEY-----post\n",
        f"pre<script>-----BEGIN PRIVATE KEY-----{token}"
        f"-----END PRIVATE KEY-----</script>post\n",
        f"literal <SCRIPT>{token}</SCRIPT> and -----BEGIN PUBLIC KEY-----"
        f"{token}-----END PUBLIC KEY-----\n",
        f"no-newline-{token}",
    ])

    for case in cases:
        assert_case(case)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
