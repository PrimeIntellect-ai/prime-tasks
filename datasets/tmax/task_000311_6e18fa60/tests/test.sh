#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import shlex
import stat
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE_PATH = "/home/user/audit_filter"
SOURCE_PATH = "/home/user/audit_filter.go"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
DECODER_PATH = "/app/decoder"


def run_filter(*args):
    return subprocess.run(
        [EXECUTABLE_PATH, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_executable_exists_and_is_executable():
    assert os.path.exists(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"Executable at {EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_filter is not a compiled ELF executable"

    assert os.path.isfile(SOURCE_PATH), f"Go source not found at {SOURCE_PATH}"
    metadata = subprocess.run(
        ["go", "version", "-m", EXECUTABLE_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert metadata.returncode == 0 and re.search(r"\bgo1\.", metadata.stdout), \
        "audit_filter does not contain Go build metadata"


def test_clean_corpus_accepted():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")

    clean_files = [
        os.path.join(CLEAN_CORPUS_DIR, f)
        for f in os.listdir(CLEAN_CORPUS_DIR)
        if f.endswith(".pub") and os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    ]
    assert len(clean_files) > 0, "No public-key files found in clean corpus directory"

    failures = []
    for filepath in clean_files:
        result = run_filter(filepath)
        if result.returncode != 0:
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files rejected (should be accepted). Offending files: {', '.join(failures)}")


def test_evil_corpus_rejected():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")

    evil_files = [
        os.path.join(EVIL_CORPUS_DIR, f)
        for f in os.listdir(EVIL_CORPUS_DIR)
        if f.endswith(".pub") and os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))
    ]
    assert len(evil_files) > 0, "No public-key files found in evil corpus directory"

    failures = []
    for filepath in evil_files:
        result = run_filter(filepath)
        if result.returncode != 1:
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed (should be rejected). Offending files: {', '.join(failures)}")


def encode_comment(text):
    return base64.b64encode(bytes(ord(c) ^ 0x5A for c in text)).decode("ascii")


def test_generated_keys_permissions_parsing_and_decoder_use():
    with tempfile.TemporaryDirectory(prefix="af-" + uuid.uuid4().hex + "-") as td:
        def generate(kind, comment, bits=None):
            path = os.path.join(td, uuid.uuid4().hex)
            command = ["ssh-keygen", "-q", "-t", kind]
            if bits is not None:
                command += ["-b", str(bits)]
            command += ["-f", path, "-N", "", "-C", comment]
            subprocess.run(command, check=True, capture_output=True, timeout=30)
            return path, path + ".pub"

        cases = []

        _, ed600 = generate("ed25519", "ordinary-" + uuid.uuid4().hex)
        os.chmod(ed600, 0o600)
        cases.append((ed600, 0, "valid Ed25519 key with mode 0600"))

        _, ed400 = generate("ed25519", "readonly-" + uuid.uuid4().hex)
        os.chmod(ed400, 0o400)
        cases.append((ed400, 0, "valid Ed25519 key with mode 0400"))

        _, rsa2048 = generate("rsa", "rsa-" + uuid.uuid4().hex, 2048)
        os.chmod(rsa2048, 0o600)
        cases.append((rsa2048, 0, "valid 2048-bit RSA key"))

        _, ecdsa = generate("ecdsa", "ecdsa-" + uuid.uuid4().hex, 256)
        os.chmod(ecdsa, 0o600)
        cases.append((ecdsa, 0, "valid ECDSA key"))

        _, broad = generate("ed25519", "broad-" + uuid.uuid4().hex)
        os.chmod(broad, 0o644)
        cases.append((broad, 1, "key with mode 0644"))

        _, rsa1024 = generate("rsa", "short-" + uuid.uuid4().hex, 1024)
        os.chmod(rsa1024, 0o600)
        cases.append((rsa1024, 1, "1024-bit RSA key"))

        _, dsa = generate("dsa", "dsa-" + uuid.uuid4().hex, 1024)
        os.chmod(dsa, 0o600)
        cases.append((dsa, 1, "deprecated DSA key"))

        invalid = os.path.join(td, uuid.uuid4().hex)
        with open(invalid, "w") as f:
            f.write("this is not an SSH public key\n")
        os.chmod(invalid, 0o600)
        cases.append((invalid, 1, "invalid public-key data"))

        private_key, _ = generate("ed25519", "private-" + uuid.uuid4().hex)
        os.chmod(private_key, 0o600)
        cases.append((private_key, 1, "private key supplied instead of a public key"))

        _, encoded_safe = generate("ed25519", encode_comment("NORMAL_" + uuid.uuid4().hex))
        os.chmod(encoded_safe, 0o600)
        cases.append((encoded_safe, 0, "comment whose decoded payload is safe"))

        _, encoded_evil = generate("ed25519", encode_comment("PREFIX_EVIL_SUFFIX_" + uuid.uuid4().hex))
        os.chmod(encoded_evil, 0o600)
        cases.append((encoded_evil, 1, "comment whose decoded payload contains EVIL"))

        for path, expected, description in cases:
            result = run_filter(path)
            assert result.returncode == expected, \
                f"Wrong status for {description}: expected {expected}, got {result.returncode}"

        assert run_filter().returncode == 1, "Invocation without an argument must exit 1"
        assert run_filter(ed600, rsa2048).returncode == 1, "Invocation with extra arguments must exit 1"

        force_evil_comment = "audit force " + uuid.uuid4().hex + " payload"
        force_safe_comment = encode_comment("EVIL_" + uuid.uuid4().hex)
        _, force_evil_key = generate("ed25519", force_evil_comment)
        _, force_safe_key = generate("ed25519", force_safe_comment)
        os.chmod(force_evil_key, 0o600)
        os.chmod(force_safe_key, 0o600)

        backup = os.path.join(td, "decoder-original-" + uuid.uuid4().hex)
        evil_marker = os.path.join(td, "called-" + uuid.uuid4().hex)
        safe_marker = os.path.join(td, "called-" + uuid.uuid4().hex)
        os.replace(DECODER_PATH, backup)
        wrapper = f'''#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = {shlex.quote(force_evil_comment)} ]; then
    : > {shlex.quote(evil_marker)}
    printf 'dynamic_PREFIX_EVIL_SUFFIX'
    exit 0
fi
if [ "$#" -eq 1 ] && [ "$1" = {shlex.quote(force_safe_comment)} ]; then
    : > {shlex.quote(safe_marker)}
    printf 'DYNAMIC_SAFE_OUTPUT'
    exit 0
fi
exec {shlex.quote(backup)} "$@"
'''
        try:
            with open(DECODER_PATH, "w") as f:
                f.write(wrapper)
            os.chmod(DECODER_PATH, 0o755)

            evil_result = run_filter(force_evil_key)
            safe_result = run_filter(force_safe_key)
            assert evil_result.returncode == 1, "Filter did not reject EVIL output produced by /app/decoder"
            assert safe_result.returncode == 0, "Filter did not use the safe output produced by /app/decoder"
            assert os.path.exists(evil_marker), "Filter did not invoke /app/decoder with the complete comment"
            assert os.path.exists(safe_marker), "Filter did not invoke /app/decoder for the encoded comment"
        finally:
            try:
                os.unlink(DECODER_PATH)
            except FileNotFoundError:
                pass
            os.replace(backup, DECODER_PATH)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
