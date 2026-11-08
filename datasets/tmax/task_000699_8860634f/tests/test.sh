#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/ws_server/sanitize"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"

def run_sanitizer(path):
    return subprocess.run([BINARY_PATH, path], capture_output=True, timeout=5)

def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"

def test_adversarial_corpus_evil():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No evil corpus files found."

    bypassed_files = []
    for file_path in evil_files:
        result = run_sanitizer(file_path)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(file_path))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil payloads bypassed: {', '.join(bypassed_files)}")

def test_adversarial_corpus_clean():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No clean corpus files found."

    modified_files = []
    for file_path in clean_files:
        with open(file_path, "rb") as f:
            expected_content = f.read()
        result = run_sanitizer(file_path)
        if result.returncode != 0 or result.stdout != expected_content:
            modified_files.append(os.path.basename(file_path))

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean payloads modified or rejected: {', '.join(modified_files)}")

def random_ascii(min_len=8, max_len=40):
    alphabet = string.ascii_letters + string.digits + " _-.,:;!?[]{}"
    return ''.join(secrets.choice(alphabet) for _ in range(random.randint(min_len, max_len))).encode()

def mixed_case_script():
    return ''.join(secrets.choice((c.lower(), c.upper())) for c in "script").encode()

def test_runtime_generated_hidden_payloads():
    nonce = secrets.token_hex(16).encode()
    clean_payloads = [
        b"runtime clean " + nonce,
        b"prefix execute(" + nonce + b" suffix",
        b"prefix exec_function(" + nonce + b" suffix",
        b"prefix EXEC(" + nonce + b" suffix",
        b"<p>safe unicode: \xe2\˜\x83 \xf0\x9f\x8c\x8d " + nonce + b"</p>",
        b"line one\nline two\r\n" + nonce + b"\n",
        b"",
    ]

    evil_payloads = [
        random_ascii() + b"\x00" + nonce + random_ascii(),
        b"\x00" + nonce,
        nonce + b"\x00",
        random_ascii() + b"exec(" + nonce + random_ascii(),
        b"exec(" + nonce,
        random_ascii() + b"<" + mixed_case_script() + b">" + nonce + b"</script>" + random_ascii(),
        random_ascii() + b"<" + mixed_case_script() + b" src=\"" + nonce + b".js\">" + random_ascii(),
        b"<" + mixed_case_script() + b" type='text/javascript'>" + nonce,
    ]

    for _ in range(12):
        clean_payloads.append(random_ascii() + nonce + random_ascii())
        marker = secrets.choice((b"\x00", b"exec(", b"<" + mixed_case_script() + b">"))
        evil_payloads.append(random_ascii() + marker + random_ascii())

    with tempfile.TemporaryDirectory(prefix="sanitizer-hidden-" + secrets.token_hex(8) + "-") as directory:
        cases = [(payload, True) for payload in clean_payloads] + [(payload, False) for payload in evil_payloads]
        random.SystemRandom().shuffle(cases)

        for index, (payload, is_clean) in enumerate(cases):
            filename = secrets.token_hex(12) + f"-{index}.payload"
            path = os.path.join(directory, filename)
            with open(path, "wb") as f:
                f.write(payload)

            result = run_sanitizer(path)
            if is_clean:
                assert result.returncode == 0, f"Generated clean payload was rejected: {filename}"
                assert result.stdout == payload, f"Generated clean payload was modified: {filename}"
            else:
                assert result.returncode == 1, f"Generated malicious payload bypassed sanitizer: {filename}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
