#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/filter.py"
POLICY_PATH = Path("/home/user/policy.ini")
MAGIC = b"ARTF\x00\x01\x00\x00"


def run_filter(artifact_path):
    result = subprocess.run(["python3", SCRIPT_PATH, artifact_path], capture_output=True)
    return result.returncode


def make_bundle(path, data_chunks, macro_string):
    encoded = bytes(b ^ 0x5A for b in macro_string.encode("utf-8"))
    with open(path, "wb") as f:
        f.write(MAGIC)
        for data in data_chunks:
            f.write(struct.pack("<I", len(data)))
            f.write(b"\x01")
            f.write(data)
        if encoded:
            split = max(1, len(encoded) // 2)
            for chunk in (encoded[:split], encoded[split:]):
                if chunk:
                    f.write(struct.pack("<I", len(chunk)))
                    f.write(b"\x02")
                    f.write(chunk)


def prepare_test_corpus():
    root = Path("/tmp/test_corpus")
    shutil.rmtree(root, ignore_errors=True)
    (root / "clean").mkdir(parents=True)
    (root / "evil").mkdir(parents=True)

    suffix = secrets.token_hex(6)
    make_bundle(root / "clean" / f"vendor_{suffix}.dat", [os.urandom(19)], "DISPLAY_STATUS")
    make_bundle(root / "clean" / f"empty_{suffix}.pkg", [os.urandom(7)], "")
    make_bundle(root / "evil" / f"vendor_{secrets.token_hex(6)}.dat", [os.urandom(13)], "PREFIX_OS_EXEC_SUFFIX")
    make_bundle(root / "evil" / f"archive_{secrets.token_hex(6)}.pkg", [os.urandom(23)], "RUN_DROP_TABLE_NOW")


prepare_test_corpus()


def test_filter_exists():
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/filter.py does not exist."


def test_clean_corpus():
    clean_dirs = ["/home/user/corpus/clean", "/tmp/test_corpus/clean"]
    failed_files = []
    total_files = 0

    for clean_dir in clean_dirs:
        if not os.path.isdir(clean_dir):
            continue
        for filename in os.listdir(clean_dir):
            filepath = os.path.join(clean_dir, filename)
            if os.path.isfile(filepath):
                total_files += 1
                exit_code = run_filter(filepath)
                if exit_code != 0:
                    failed_files.append(filename)

    assert len(failed_files) == 0, f"{len(failed_files)} of {total_files} clean modified/rejected. Offending files: {', '.join(failed_files)}"


def test_evil_corpus():
    evil_dirs = ["/home/user/corpus/evil", "/tmp/test_corpus/evil"]
    failed_files = []
    total_files = 0

    for evil_dir in evil_dirs:
        if not os.path.isdir(evil_dir):
            continue
        for filename in os.listdir(evil_dir):
            filepath = os.path.join(evil_dir, filename)
            if os.path.isfile(filepath):
                total_files += 1
                exit_code = run_filter(filepath)
                if exit_code != 1:
                    failed_files.append(filename)

    assert len(failed_files) == 0, f"{len(failed_files)} of {total_files} evil bypassed. Offending files: {', '.join(failed_files)}"


def test_generated_bundles_in_neutral_location():
    root = Path(tempfile.mkdtemp(prefix="artifact_inputs_"))
    try:
        cases = [
            ("PRINT SAFE MESSAGE", 0),
            ("", 0),
            ("BEFORE_OS_EXEC_AFTER", 1),
            ("DROP_TABLE confidential_records", 1),
            ('INIT_REVERSE_SHELL("192.0.2.8")', 1),
        ]
        random.shuffle(cases)
        for macro, expected in cases:
            path = root / f"{secrets.token_hex(12)}.bundle"
            make_bundle(path, [os.urandom(5), os.urandom(17)], macro)
            assert run_filter(str(path)) == expected, f"Incorrect classification for generated bundle {path.name}"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_policy_is_read_and_applied():
    original_policy = POLICY_PATH.read_bytes()
    root = Path(tempfile.mkdtemp(prefix="incoming_artifacts_"))
    random_forbidden = "BLOCK_" + secrets.token_hex(12).upper()
    try:
        POLICY_PATH.write_text(f"[Policy]\nForbidden = {random_forbidden}\n", encoding="utf-8")

        cases = [
            (f"START_{random_forbidden}_END", 1),
            ("OS_EXEC", 0),
            ("ALLOW_" + secrets.token_hex(12).upper(), 0),
        ]
        random.shuffle(cases)
        for macro, expected in cases:
            path = root / f"{secrets.token_hex(10)}.bin"
            make_bundle(path, [os.urandom(11)], macro)
            assert run_filter(str(path)) == expected, f"Filter did not apply the active policy for {path.name}"
    finally:
        POLICY_PATH.write_bytes(original_policy)
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
