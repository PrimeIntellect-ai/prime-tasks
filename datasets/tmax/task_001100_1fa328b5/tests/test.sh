#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import string
import subprocess
import tempfile
import pytest

EXPECTED_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
HASH_FILE = "/home/user/archive_hash.txt"
ARCHIVE_FILE = "/app/logs.tar.gz"
SCRIPT_FILE = "/home/user/filter_logs.sh"
CLEAN_CORPUS_DIR = "/app/verifier/corpus/clean"
EVIL_CORPUS_DIR = "/app/verifier/corpus/evil"

MALICIOUS_STRINGS = [
    "<script>",
    "javascript:",
    "onerror=",
    "' or 1=1",
    "union select",
]


def test_archive_hash_file():
    assert os.path.isfile(HASH_FILE), f"Missing required hash file: {HASH_FILE}"
    with open(HASH_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_HASH, (
        f"Hash file content is incorrect. Expected {EXPECTED_HASH}, got {content}"
    )


def test_archive_really_matches_hash():
    assert os.path.isfile(ARCHIVE_FILE), f"Missing archive: {ARCHIVE_FILE}"
    digest = hashlib.sha256()
    with open(ARCHIVE_FILE, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    assert actual == EXPECTED_HASH, (
        f"Archive SHA-256 does not match the spoken hash: expected {EXPECTED_HASH}, got {actual}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_FILE), f"Missing required script file: {SCRIPT_FILE}"
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script file is not executable: {SCRIPT_FILE}"


def process_line_python(line):
    lower_line = line.lower()
    for bad in MALICIOUS_STRINGS:
        if bad in lower_line:
            return None
    return re.sub(r"\d{3}-\d{2}-\d{4}", "XXX-XX-XXXX", line)


def get_expected_output(filepath):
    expected_lines = []
    with open(filepath, "r") as f:
        for line in f:
            processed = process_line_python(line)
            if processed is not None:
                expected_lines.append(processed)
    return "".join(expected_lines)


def run_filter(filepath):
    return subprocess.run(
        [SCRIPT_FILE, filepath], capture_output=True, text=True, timeout=10
    )


def test_clean_corpus():
    if not os.path.isdir(CLEAN_CORPUS_DIR):
        pytest.skip(f"Clean corpus directory not found: {CLEAN_CORPUS_DIR}")
    files = [
        f for f in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    ]
    if not files:
        pytest.skip("No files found in clean corpus.")
    modified_files = []
    for filename in files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, "r") as f:
            expected_output = f.read()
        result = run_filter(filepath)
        if result.returncode != 0 or result.stdout != expected_output:
            modified_files.append(filename)
    assert not modified_files, (
        f"{len(modified_files)} of {len(files)} clean modified. "
        f"Offending files: {', '.join(modified_files)}"
    )


def test_evil_corpus():
    if not os.path.isdir(EVIL_CORPUS_DIR):
        pytest.skip(f"Evil corpus directory not found: {EVIL_CORPUS_DIR}")
    files = [
        f for f in os.listdir(EVIL_CORPUS_DIR)
        if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))
    ]
    if not files:
        pytest.skip("No files found in evil corpus.")
    bypassed_files = []
    for filename in files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        expected_output = get_expected_output(filepath)
        result = run_filter(filepath)
        if result.returncode != 0 or result.stdout != expected_output:
            bypassed_files.append(filename)
    assert not bypassed_files, (
        f"{len(bypassed_files)} of {len(files)} evil bypassed. "
        f"Offending files: {', '.join(bypassed_files)}"
    )


def mixed_case(value, rng):
    return "".join(
        ch.upper() if ch.isalpha() and rng.choice((True, False)) else ch.lower()
        if ch.isalpha() else ch
        for ch in value
    )


def test_unseen_randomized_files():
    rng = random.SystemRandom()
    nonce = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(24))
    safe_templates = [
        "Session {n} completed successfully.\n",
        "Account note {n}: punctuation !@#$%^&*() remains unchanged.\n",
        "Employee {n} supplied SSN 123-45-6789 and backup 987-65-4321.\n",
        "Literal text script and javascript without a colon is safe: {n}.\n",
        "Database words UNION and SELECT are separated here: {n}.\n",
    ]
    bad_templates = [
        "prefix {token} suffix {n} SSN 111-22-3333\n",
        "{n} before payload {token} after payload\n",
    ]

    with tempfile.TemporaryDirectory(prefix="compliance-unseen-") as directory:
        for index in range(12):
            lines = []
            for template in safe_templates:
                lines.append(template.format(n=f"{nonce}-{index}"))
            for token in MALICIOUS_STRINGS:
                varied = mixed_case(token, rng)
                template = rng.choice(bad_templates)
                lines.append(template.format(token=varied, n=f"{nonce}-{index}"))
            rng.shuffle(lines)
            filename = "input-" + "".join(
                rng.choice(string.ascii_letters + string.digits) for _ in range(20)
            ) + ".log"
            filepath = os.path.join(directory, filename)
            with open(filepath, "w") as f:
                f.writelines(lines)
            expected = get_expected_output(filepath)
            result = run_filter(filepath)
            assert result.returncode == 0, (
                f"Filter exited with {result.returncode} on unseen input; stderr={result.stderr!r}"
            )
            assert result.stdout == expected, (
                f"Incorrect filtering on unseen randomized input {filename}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
