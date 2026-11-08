#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"
ORACLE_PATH = "/app/validator_oracle"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"


def test_sanitizer_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_adversarial_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def _make_artifact(workdir, base_elf, payload, decoy=None):
    token = secrets.token_hex(12)
    payload_path = os.path.join(workdir, token + ".bin")
    elf_path = os.path.join(workdir, token + ".obj")
    gz_path = os.path.join(workdir, token + ".dat")

    with open(payload_path, "wb") as f:
        f.write(payload)
    subprocess.run(
        ["objcopy", "--add-section", f".note.artifact={payload_path}", base_elf, elf_path],
        check=True,
        capture_output=True,
    )

    if decoy is not None:
        decoy_path = os.path.join(workdir, secrets.token_hex(12) + ".bin")
        next_elf = os.path.join(workdir, secrets.token_hex(12) + ".obj")
        with open(decoy_path, "wb") as f:
            f.write(decoy)
        subprocess.run(
            ["objcopy", "--add-section", f".note.decoy={decoy_path}", elf_path, next_elf],
            check=True,
            capture_output=True,
        )
        os.replace(next_elf, elf_path)

    with open(elf_path, "rb") as src, gzip.open(gz_path, "wb") as dst:
        shutil.copyfileobj(src, dst)
    return gz_path


def _read_log(path):
    if not os.path.exists(path):
        return []
    data = open(path, "rb").read()
    records = []
    offset = 0
    while offset < len(data):
        assert offset + 8 <= len(data), "Malformed oracle invocation log"
        size = struct.unpack(">Q", data[offset:offset + 8])[0]
        offset += 8
        assert offset + size <= len(data), "Malformed oracle invocation log"
        records.append(data[offset:offset + size])
        offset += size
    return records


def test_randomized_artifacts_and_oracle_use():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle is not executable: {ORACLE_PATH}"

    marker = b"R\x000\x00G\x00U\x00E\x00"
    with tempfile.TemporaryDirectory(prefix="artifact-check-") as workdir:
        source = os.path.join(workdir, "base.c")
        base_elf = os.path.join(workdir, "base.bin")
        with open(source, "w") as f:
            f.write("int main(void) { return 0; }\n")
        subprocess.run(["gcc", source, "-o", base_elf], check=True, capture_output=True)

        cases = [
            (b"SAFE\x00" + secrets.token_bytes(24), None),
            (marker + secrets.token_bytes(13), None),
            (secrets.token_bytes(11) + marker + secrets.token_bytes(9), None),
            (b"plain ASCII R0GUE is not UTF-16LE", None),
            (b"R\x000\x00G\x00U", None),
            (b"ordinary-section-" + secrets.token_bytes(12), marker),
            (secrets.token_bytes(7) + marker + b"tail", b"harmless decoy"),
        ]

        saved_oracle = os.path.join(workdir, "real-oracle")
        os.replace(ORACLE_PATH, saved_oracle)
        try:
            expected = []
            for payload, _ in cases:
                result = subprocess.run([saved_oracle], input=payload, capture_output=True)
                assert result.returncode in (0, 1), "Oracle returned an invalid classification"
                expected.append(result.returncode)
            assert 0 in expected and 1 in expected, "Oracle failed classification sanity check"

            log_path = os.path.join(workdir, "oracle-calls.bin")
            wrapper = """#!/usr/bin/python3
import struct
import subprocess
import sys

data = sys.stdin.buffer.read()
with open(%r, "ab") as f:
    f.write(struct.pack(">Q", len(data)))
    f.write(data)
result = subprocess.run([%r], input=data)
sys.exit(result.returncode)
""" % (log_path, saved_oracle)
            with open(ORACLE_PATH, "w") as f:
                f.write(wrapper)
            os.chmod(ORACLE_PATH, 0o755)

            generated = [
                (_make_artifact(workdir, base_elf, payload, decoy), payload, answer)
                for (payload, decoy), answer in zip(cases, expected)
            ]

            for artifact, payload, answer in generated:
                if os.path.exists(log_path):
                    os.remove(log_path)
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, artifact],
                    capture_output=True,
                    timeout=10,
                )
                assert result.returncode == answer, (
                    f"Incorrect classification for randomized artifact: expected {answer}, "
                    f"got {result.returncode}"
                )
                calls = _read_log(log_path)
                assert payload in calls, (
                    "The validator oracle was not invoked with the raw .note.artifact section"
                )
        finally:
            if os.path.lexists(ORACLE_PATH):
                os.remove(ORACLE_PATH)
            os.replace(saved_oracle, ORACLE_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
