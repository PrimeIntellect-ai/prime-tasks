#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import base64
import os
import secrets
import stat
import string
import subprocess
import tempfile
import pytest

FILTER_BIN = "/home/user/filter_bin"
FILTER_SOURCE = "/home/user/payload_filter.cpp"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def test_filter_bin_exists_and_permissions():
    assert os.path.isfile(FILTER_BIN), f"The binary {FILTER_BIN} does not exist."

    st = os.stat(FILTER_BIN)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o755, f"Permissions of {FILTER_BIN} are {oct(permissions)}, expected 0o755."


def test_cpp_source_and_compiled_binary():
    assert os.path.isfile(FILTER_SOURCE), f"The C++ source {FILTER_SOURCE} does not exist."
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FILTER_BIN} is not a compiled ELF binary."


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} is missing."

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}."

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil payloads bypassed (expected exit code 1). Offending files: {', '.join(failed_files)}")


def test_clean_corpus_preserved():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} is missing."

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([FILTER_BIN, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean payloads modified/rejected (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_filter_on_randomized_neutral_paths():
    key = b"SecretKeyAabcd1234"
    alphabet = string.ascii_letters + string.digits + " _-:=,{}[]()"

    def encrypt(data):
        encrypted = bytes(data[i] ^ key[i % len(key)] for i in range(len(data)))
        return base64.b64encode(encrypted)

    cases = []
    for expected, marker in ([(0, None)] * 16 + [(1, "EXEC_SHELL")] * 8 + [(1, "../")] * 8):
        length = 60 + secrets.randbelow(140)
        plaintext = "".join(secrets.choice(alphabet) for _ in range(length))
        if marker is not None:
            position = secrets.randbelow(length - len(marker) + 1)
            plaintext = plaintext[:position] + marker + plaintext[position + len(marker):]
        cases.append((expected, encrypt(plaintext.encode("ascii"))))

    secrets.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="payload_filter_") as directory:
        failures = []
        for expected, payload in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(payload)
            result = subprocess.run([FILTER_BIN, path], capture_output=True, timeout=5)
            if result.returncode != expected:
                failures.append((os.path.basename(path), expected, result.returncode))

        if failures:
            pytest.fail(f"Filter misclassified randomized payloads on neutral paths: {failures}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
