#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import string
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/validator"
SOURCE = "/home/user/policy_validator.cpp"


def run_validator(executable, *args):
    return subprocess.run(
        [executable, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def make_policy(body, digest=None):
    if isinstance(body, str):
        body = body.encode("utf-8")
    if digest is None:
        digest = hashlib.sha256(body).hexdigest()
    return b"HASH: " + digest.encode("ascii") + b"\n" + body


def random_token(prefix="Token"):
    alphabet = string.ascii_letters + string.digits
    return prefix + "".join(secrets.choice(alphabet) for _ in range(18))


@pytest.fixture(scope="session")
def rebuilt_validator(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"Missing validator source: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, f"Validator source is empty: {SOURCE}"
    output = tmp_path_factory.mktemp("build") / "validator_from_source"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "policy_validator.cpp does not compile:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    return str(output)


def test_red_frame_count():
    count_file = "/home/user/red_frame_count.txt"
    assert os.path.isfile(count_file), f"Missing red frame count file: {count_file}"
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content == "47", f"Expected red frame count to be '47', but got '{content}'"


def test_validator_executable_exists():
    executable = EXECUTABLE
    assert os.path.isfile(executable), f"Missing validator executable: {executable}"
    assert os.access(executable, os.X_OK), f"Validator executable is not executable: {executable}"


def test_validator_source_exists_and_compiles(rebuilt_validator):
    assert os.path.isfile(SOURCE), f"Missing validator source: {SOURCE}"
    assert os.access(rebuilt_validator, os.X_OK)


def test_validator_clean_corpus():
    executable = EXECUTABLE
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    failed_clean = []
    for filepath in clean_files:
        result = run_validator(executable, filepath)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(filepath))

    assert len(failed_clean) == 0, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}"


def test_validator_evil_corpus():
    executable = EXECUTABLE
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    bypassed_evil = []
    for filepath in evil_files:
        result = run_validator(executable, filepath)
        if result.returncode == 0:
            bypassed_evil.append(os.path.basename(filepath))

    assert len(bypassed_evil) == 0, f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}"


def test_generated_policy_files(rebuilt_validator):
    middle = random_token("CA")
    nonce = random_token("nonce")
    safe_body = (
        f"COMMENT: {nonce}\n"
        f"CSP: default-src 'self'; img-src https://{nonce}.example\n"
        f"CERT_CHAIN: RootCA,{middle},LeafCA\n"
    ).encode()
    minimal_body = b"CSP: object-src 'none'\nCERT_CHAIN: RootCA,LeafCA"

    semantic_cases = [
        (True, safe_body),
        (True, minimal_body),
        (False, f"CSP: script-src 'unsafe-inline' {nonce}\nCERT_CHAIN: RootCA,{middle},LeafCA".encode()),
        (False, f"CSP: script-src 'unsafe-eval' {nonce}\nCERT_CHAIN: RootCA,{middle},LeafCA".encode()),
        (False, f"CSP: default-src 'self'\nCERT_CHAIN: {middle},LeafCA".encode()),
        (False, f"CSP: default-src 'self'\nCERT_CHAIN: RootCA,{middle}".encode()),
        (False, f"CSP: default-src 'self'\nCERT_CHAIN: RootCA,{middle},RevokedCA,LeafCA".encode()),
        (False, f"COMMENT: {nonce}\nCERT_CHAIN: RootCA,{middle},LeafCA".encode()),
        (False, f"CSP: default-src 'self'\nCOMMENT: {nonce}".encode()),
        (False, b"CSP: default-src 'self'\nCERT_CHAIN: RootCA,LeafCA,ExtraCA"),
        (False, b"CSP: default-src 'self'\nCERT_CHAIN: ExtraCA,RootCA,LeafCA"),
        (False, b" CSP: default-src 'self'\nCERT_CHAIN: RootCA,LeafCA"),
        (False, b"CSP: default-src 'self'\n CERT_CHAIN: RootCA,LeafCA"),
    ]

    files = []
    with tempfile.TemporaryDirectory(prefix="policy_checks_") as directory:
        for expected_valid, body in semantic_cases:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "wb") as handle:
                handle.write(make_policy(body))
            files.append((path, expected_valid))

        bad_hash_body = f"CSP: default-src 'self'\nCERT_CHAIN: RootCA,{middle},LeafCA".encode()
        wrong_digest = hashlib.sha256(bad_hash_body + b"tampered").hexdigest()
        path = os.path.join(directory, uuid.uuid4().hex)
        with open(path, "wb") as handle:
            handle.write(make_policy(bad_hash_body, wrong_digest))
        files.append((path, False))

        malformed_headers = [
            b"HASH:" + hashlib.sha256(minimal_body).hexdigest().encode() + b"\n" + minimal_body,
            b"HASH: xyz\n" + minimal_body,
            b"HASH: " + (b"0" * 63) + b"\n" + minimal_body,
            b"NOT_HASH: " + hashlib.sha256(minimal_body).hexdigest().encode() + b"\n" + minimal_body,
            b"HASH: " + hashlib.sha256(b"").hexdigest().encode(),
            b"",
        ]
        for content in malformed_headers:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "wb") as handle:
                handle.write(content)
            files.append((path, False))

        random.SystemRandom().shuffle(files)
        for executable in (EXECUTABLE, rebuilt_validator):
            for path, expected_valid in files:
                result = run_validator(executable, path)
                if expected_valid:
                    assert result.returncode == 0, f"Rejected generated valid policy {os.path.basename(path)}"
                else:
                    assert result.returncode != 0, f"Accepted generated invalid policy {os.path.basename(path)}"


def test_validator_rejects_bad_invocations(rebuilt_validator):
    missing = os.path.join(tempfile.gettempdir(), "missing_" + uuid.uuid4().hex)
    with tempfile.TemporaryDirectory(prefix="not_a_policy_") as directory:
        for executable in (EXECUTABLE, rebuilt_validator):
            assert run_validator(executable).returncode != 0, "Validator accepted a missing path argument"
            assert run_validator(executable, missing).returncode != 0, "Validator accepted a nonexistent file"
            assert run_validator(executable, directory).returncode != 0, "Validator accepted a directory"
            assert run_validator(executable, missing, missing).returncode != 0, "Validator accepted extra arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
