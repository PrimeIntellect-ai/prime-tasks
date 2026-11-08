#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tempfile

BASE = "/home/user/vuln_scan"
SOURCE = os.path.join(BASE, "cracker.cpp")
SUBMITTED_BINARY = os.path.join(BASE, "cracker")
HASHES = os.path.join(BASE, "hashes.txt")
CRACKED = os.path.join(BASE, "cracked.txt")
SALT = "H4rdC0d3d_S@1t!"


def test_cracker_cpp_exists():
    """Check if the student created the cracker.cpp source file."""
    assert os.path.exists(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."


def test_cracker_binary_exists():
    """Check that the requested compiled cracker exists and is executable."""
    assert os.path.exists(SUBMITTED_BINARY), f"Compiled cracker {SUBMITTED_BINARY} is missing."
    assert os.path.isfile(SUBMITTED_BINARY), f"{SUBMITTED_BINARY} is not a regular file."
    assert os.access(SUBMITTED_BINARY, os.X_OK), f"{SUBMITTED_BINARY} is not executable."


def test_cracked_txt_exists():
    """Check if the output file cracked.txt was generated."""
    assert os.path.exists(CRACKED), f"Output file {CRACKED} is missing."
    assert os.path.isfile(CRACKED), f"{CRACKED} is not a regular file."


def test_cracked_txt_contents():
    """Validate that cracked.txt contains the correct hash:PIN mappings in the correct order."""
    assert os.path.exists(HASHES), f"{HASHES} is missing."
    assert os.path.exists(CRACKED), f"{CRACKED} is missing."

    with open(HASHES, 'r') as f:
        original_hashes = f.read().splitlines()

    with open(CRACKED, 'r') as f:
        cracked_lines = f.read().splitlines()

    assert len(cracked_lines) == len(original_hashes), f"Expected {len(original_hashes)} lines in {CRACKED}, but found {len(cracked_lines)}."

    expected_pins = ["0451", "1337", "4920", "8080", "9999"]
    expected_mappings = []
    for pin in expected_pins:
        h = hashlib.sha256((SALT + pin).encode('utf-8')).hexdigest()
        expected_mappings.append(f"{h}:{pin}")

    for i, (expected, actual) in enumerate(zip(expected_mappings, cracked_lines)):
        assert actual == expected, f"Line {i+1} in {CRACKED} is incorrect. Expected '{expected}', got '{actual}'."


def test_source_compiles_and_crackers_handle_derived_inputs():
    """Compile the submitted source and exercise both requested artifacts on fresh hashes."""
    build_dir = tempfile.mkdtemp(prefix="cracker_verify_")
    rebuilt_binary = os.path.join(build_dir, "cracker")

    with open(HASHES, "rb") as f:
        saved_hashes = f.read()
    cracked_existed = os.path.exists(CRACKED)
    saved_cracked = None
    if cracked_existed:
        with open(CRACKED, "rb") as f:
            saved_cracked = f.read()

    try:
        compile_result = subprocess.run(
            ["g++", "-O3", SOURCE, "-lcrypto", "-o", rebuilt_binary],
            cwd=BASE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"cracker.cpp failed to compile:\n{compile_result.stderr}"

        pins = []
        while len(pins) < 4:
            pin = f"{secrets.randbelow(10000):04d}"
            if pin not in pins:
                pins.append(pin)

        challenge_hashes = [hashlib.sha256((SALT + pin).encode("utf-8")).hexdigest() for pin in pins]
        expected = [f"{h}:{pin}" for h, pin in zip(challenge_hashes, pins)]

        for executable in (SUBMITTED_BINARY, rebuilt_binary):
            with open(HASHES, "w", encoding="utf-8") as f:
                f.write("\n".join(challenge_hashes) + "\n")
            if os.path.exists(CRACKED):
                os.remove(CRACKED)

            with open(CRACKED, "w", encoding="utf-8") as stdout_file:
                try:
                    result = subprocess.run(
                        [executable],
                        cwd=BASE,
                        stdin=subprocess.DEVNULL,
                        stdout=stdout_file,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=30,
                    )
                except subprocess.TimeoutExpired:
                    assert False, f"{executable} timed out on four 4-digit PIN hashes."

            assert result.returncode == 0, f"{executable} exited with status {result.returncode}: {result.stderr}"
            assert os.path.isfile(CRACKED), f"{executable} did not produce cracked.txt."
            with open(CRACKED, "r", encoding="utf-8") as f:
                actual = f.read().splitlines()
            assert actual == expected, f"{executable} produced incorrect results for verifier-derived hashes."
    finally:
        with open(HASHES, "wb") as f:
            f.write(saved_hashes)
        if cracked_existed:
            with open(CRACKED, "wb") as f:
                f.write(saved_cracked)
        elif os.path.exists(CRACKED):
            os.remove(CRACKED)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
