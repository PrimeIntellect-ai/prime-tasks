#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

BASE_DIR = "/home/user/cfg_manager"
RAW_DIR = os.path.join(BASE_DIR, "raw")
EXTRACTED_DIR = os.path.join(BASE_DIR, "extracted")
FINAL_CONFIG = os.path.join(BASE_DIR, "final_config.txt")
EXTRACTOR_C = os.path.join(BASE_DIR, "extractor.c")

def test_step1_renaming():
    """Verify that the raw files were renamed from .dat to .cpk."""
    assert os.path.isdir(RAW_DIR), f"Raw directory {RAW_DIR} is missing."

    dat_files = [f for f in os.listdir(RAW_DIR) if f.endswith(".dat")]
    assert not dat_files, f"Found .dat files that should have been renamed: {dat_files}"

    cpk_files = [f for f in os.listdir(RAW_DIR) if f.endswith(".cpk")]
    assert "archive_01.cpk" in cpk_files, "archive_01.cpk is missing."
    assert "archive_02.cpk" in cpk_files, "archive_02.cpk is missing."

def test_step2_c_program_exists():
    """Verify that the C program was created."""
    assert os.path.isfile(EXTRACTOR_C), f"C program {EXTRACTOR_C} is missing."

def test_step3_extracted_files():
    """Verify that the files were extracted and updated correctly."""
    assert os.path.isdir(EXTRACTED_DIR), f"Extracted directory {EXTRACTED_DIR} is missing."

    expected_files = {"alpha.conf", "beta.conf", "gamma.conf", "delta.conf"}
    actual_files = set(os.listdir(EXTRACTED_DIR))

    assert expected_files.issubset(actual_files), f"Missing extracted files. Expected {expected_files}, found {actual_files}"

    alpha_path = os.path.join(EXTRACTED_DIR, "alpha.conf")
    with open(alpha_path, "r") as f:
        content = f.read()
        assert "db_host=db-cluster.aws.internal" in content, f"db_host was not updated in {alpha_path}"
        assert "legacy-db.local" not in content, f"legacy-db.local was not completely replaced in {alpha_path}"

def test_step4_final_config_content():
    """Verify the final merged configuration file."""
    assert os.path.isfile(FINAL_CONFIG), f"Final configuration file {FINAL_CONFIG} is missing."

    expected_content = (
        "=== alpha.conf ===\n"
        "loglevel=info\n"
        "db_host=db-cluster.aws.internal\n"
        "max_conns=100\n"
        "=== beta.conf ===\n"
        "timeout=30\n"
        "db_host=db-cluster.aws.internal\n"
        "=== delta.conf ===\n"
        "cache_size=1024\n"
        "db_host=db-cluster.aws.internal\n"
        "=== gamma.conf ===\n"
        "enable_feature_x=true\n"
    )

    with open(FINAL_CONFIG, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, (
        "The contents of final_config.txt do not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_extractor_behavior.py
import glob
import os
import secrets
import struct
import subprocess

BASE = "/home/user/cfg_manager"
RAW = os.path.join(BASE, "raw")
OUT = os.path.join(BASE, "extracted")
SOURCE = os.path.join(BASE, "extractor.c")
BINARY = "/tmp/cfg_extractor_verifier"

token = secrets.token_hex(8)
name1 = f"verify_{token}_a.conf"
name2 = f"verify_{token}_b.conf"
first = f"token={secrets.token_hex(16)}\nchoice=first\n".encode()
duplicate = f"token={secrets.token_hex(16)}\nchoice=duplicate\n".encode()
second = f"token={secrets.token_hex(16)}\nchoice=second\n".encode()
archive = os.path.join(RAW, f"archive_verify_{token}.cpk")
targets = [os.path.join(OUT, name1), os.path.join(OUT, name2)]

def entry(name, data):
    encoded = name.encode()
    assert len(encoded) < 64
    return encoded.ljust(64, b"\0") + struct.pack("<I", len(data)) + data

try:
    subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    with open(archive, "wb") as f:
        f.write(b"CFGPAK01")
        f.write(struct.pack("<I", 3))
        f.write(entry(name1, first))
        f.write(entry(name1, duplicate))
        f.write(entry(name2, second))

    commands = [
        ([BINARY, archive], BASE),
        ([BINARY, archive, OUT], BASE),
        ([BINARY, os.path.basename(archive)], RAW),
        ([BINARY], BASE),
        ([BINARY] + sorted(glob.glob(os.path.join(RAW, "*.cpk"))), BASE),
    ]

    passed = False
    diagnostics = []
    for command, cwd in commands:
        for target in targets:
            try:
                os.remove(target)
            except FileNotFoundError:
                pass
        try:
            result = subprocess.run(
                command,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            diagnostics.append((command, result.returncode))
        except (subprocess.SubprocessError, OSError) as exc:
            diagnostics.append((command, repr(exc)))
            continue

        if not all(os.path.isfile(target) for target in targets):
            continue
        with open(targets[0], "rb") as f:
            actual_first = f.read()
        with open(targets[1], "rb") as f:
            actual_second = f.read()
        if actual_first == first and actual_second == second:
            passed = True
            break

    assert passed, (
        "The compiled extractor did not parse a newly generated ConfigPak archive "
        "and preserve only the first duplicate occurrence. Attempts: " + repr(diagnostics)
    )
finally:
    for path in [archive, BINARY] + targets:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
BEHAVIOR_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_extractor_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
