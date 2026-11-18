#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

VALIDATOR_BIN = "/home/user/validator"
VALIDATOR_SOURCE = "/home/user/validator.go"
EVIL_DIR = "/home/user/payloads/evil"
CLEAN_DIR = "/home/user/payloads/clean"

EXPECTED_CORPUS = {
    "clean/user1.txt": b"user1_newpass123\n",
    "clean/user2.txt": b"secure_password_456\n",
    "clean/user3.txt": b"alphanumeric789\n",
    "clean/user4.txt": b"justletters\n",
    "clean/user5.txt": b"1234567890\n",
    "evil/sqli1.txt": b"' OR 1=1 --\n",
    "evil/sqli2.txt": b"admin' #\n",
    "evil/xss1.txt": b"<script>alert(1)</script>\n",
    "evil/xss2.txt": b"<img src=x onerror=alert(1)>\n",
    "evil/cmd1.txt": b"; rm -rf /\n",
}


def run_validator(path):
    return subprocess.run(
        [VALIDATOR_BIN, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_validator_binary_exists():
    assert os.path.isfile(VALIDATOR_BIN), f"Validator binary not found at {VALIDATOR_BIN}"
    assert os.access(VALIDATOR_BIN, os.X_OK), f"Validator binary at {VALIDATOR_BIN} is not executable"
    with open(VALIDATOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Validator is not a compiled Linux executable"
    assert os.path.isfile(VALIDATOR_SOURCE), f"Go source not found at {VALIDATOR_SOURCE}"
    go_version = subprocess.run(
        ["go", "version", VALIDATOR_BIN], capture_output=True, text=True, timeout=5
    )
    assert go_version.returncode == 0 and "go1" in go_version.stdout.lower(), \
        "Validator is not a compiled Go executable"


def test_payload_directories_exist():
    assert os.path.isdir(EVIL_DIR), f"Evil payloads directory not found at {EVIL_DIR}. Did the agent decrypt and extract the archive correctly?"
    assert os.path.isdir(CLEAN_DIR), f"Clean payloads directory not found at {CLEAN_DIR}. Did the agent decrypt and extract the archive correctly?"


def test_extracted_archive_contents():
    for relative_path, expected in EXPECTED_CORPUS.items():
        path = os.path.join("/home/user/payloads", relative_path)
        assert os.path.isfile(path), f"Expected extracted file is missing: {relative_path}"
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Extracted file has incorrect contents: {relative_path}"


def test_adversarial_corpus():
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, f"No files found in {EVIL_DIR}"
    assert len(clean_files) > 0, f"No files found in {CLEAN_DIR}"

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        result = run_validator(filepath)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        result = run_validator(filepath)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(filepath))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean rejected: {', '.join(clean_modified)}")

    assert not evil_bypassed and not clean_modified, "Adversarial corpus validation failed:\n" + "\n".join(error_messages)


def test_validator_on_neutral_randomized_paths():
    token = secrets.token_hex(8)
    number = random.randint(10000, 99999)
    cases = [
        (f"credential_{token}_A19", 0),
        (f"user{number}_newpass_{token}", 0),
        (f"SecureToken{token}{number}", 0),
        (str(number) + token, 0),
        (f"' OR {number}={number} --", 1),
        (f"admin' # {token}", 1),
        (f"<script>alert('{token}')</script>", 1),
        (f"<img src=x onerror=alert({number})>", 1),
        (f"; echo {token}", 1),
        (f"$(echo {token})", 1),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="validator-check-") as directory:
        for content, expected_code in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write(content + "\n")
            result = run_validator(os.path.abspath(path))
            assert result.returncode == expected_code, (
                f"Validator returned {result.returncode} instead of {expected_code} "
                f"for content {content!r} at a neutral path"
            )


def test_argument_and_file_input_validation():
    no_args = subprocess.run([VALIDATOR_BIN], capture_output=True, timeout=5)
    assert no_args.returncode != 0, "Validator accepted zero command-line arguments"

    two_args = subprocess.run(
        [VALIDATOR_BIN, "/tmp/one", "/tmp/two"], capture_output=True, timeout=5
    )
    assert two_args.returncode != 0, "Validator accepted more than one command-line argument"

    missing = os.path.join(tempfile.gettempdir(), "missing-" + secrets.token_hex(12))
    result = run_validator(os.path.abspath(missing))
    assert result.returncode != 0, "Validator treated an unreadable/nonexistent input as clean"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
