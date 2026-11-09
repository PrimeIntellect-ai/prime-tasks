#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

EXECUTABLE = "/home/user/sanitizer"
CLEAN_DIR = "/app/corpus/clean/"
EVIL_DIR = "/app/corpus/evil/"

def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not marked as executable"

def test_clean_corpus_accepted():
    if not os.path.exists(EXECUTABLE):
        pytest.skip("Executable missing, cannot run corpus tests.")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus directory: {CLEAN_DIR}"

    failed_files = []
    for fpath in clean_files:
        with open(fpath, "rb") as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True)
            if result.returncode != 0:
                failed_files.append((os.path.basename(fpath), result.returncode))

    if failed_files:
        details = ", ".join([f"{name} (code {code})" for name, code in failed_files[:5]])
        if len(failed_files) > 5:
            details += f" ... and {len(failed_files) - 5} more"
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected. Examples: {details}")

def test_evil_corpus_rejected():
    if not os.path.exists(EXECUTABLE):
        pytest.skip("Executable missing, cannot run corpus tests.")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus directory: {EVIL_DIR}"

    failed_files = []
    for fpath in evil_files:
        with open(fpath, "rb") as f:
            result = subprocess.run([EXECUTABLE], stdin=f, capture_output=True)
            if result.returncode == 0:
                failed_files.append(os.path.basename(fpath))

    if failed_files:
        details = ", ".join(failed_files[:5])
        if len(failed_files) > 5:
            details += f" ... and {len(failed_files) - 5} more"
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed the sanitizer (exited with 0). Examples: {details}")

def run_payload(payload):
    return subprocess.run([EXECUTABLE], input=payload, capture_output=True).returncode

def test_generated_unseen_streams():
    for _ in range(6):
        nonce = secrets.token_hex(12).encode("ascii")

        clean_cases = [
            b"",
            b"COMMENT " + nonce + b"\n",
            b"BACKUP /etc/nginx/" + nonce + b".conf\n",
            b"SYMLINK /backup/config/" + nonce + b" /backup/config/link_" + nonce + b"\n",
            b"HARDLINK /backup/config/" + nonce + b" /backup/config/hard_" + nonce + b"\n",
            (b"COMMENT " + nonce + b"\n"
             b"BACKUP /var/lib/" + nonce + b"\n"
             b"SYMLINK /backup/config/source_" + nonce + b" /backup/config/dest_" + nonce + b"\n"),
        ]

        evil_cases = [
            b"COMMENT " + nonce + b"\xde\xad\xbe\xef trailing data",
            b"\x00" + nonce + b"\x00\xde\xad\xbe\xef\x00",
            b"BACKUP /root/" + nonce + b"\n",
            b"COMMENT " + nonce + b"\nBACKUP /root\n",
            b"SYMLINK /etc/" + nonce + b" /backup/config/link_" + nonce + b"\n",
            b"HARDLINK /var/log/" + nonce + b" /backup/config/hard_" + nonce + b"\n",
            b"SYMLINK /backup/configuration/" + nonce + b" /backup/config/link_" + nonce + b"\n",
            b"HARDLINK /backup/config-old/" + nonce + b" /backup/config/hard_" + nonce + b"\n",
        ]

        for index, payload in enumerate(clean_cases):
            code = run_payload(payload)
            assert code == 0, f"Generated clean case {index} was rejected with code {code}"

        for index, payload in enumerate(evil_cases):
            code = run_payload(payload)
            assert code != 0, f"Generated evil case {index} was accepted"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
