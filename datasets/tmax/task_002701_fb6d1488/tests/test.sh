#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import struct
import subprocess
import tempfile
import fcntl
import pytest

AGENT_SCRIPT = "/home/user/extract_configs.py"
ORACLE_BINARY = "/tests/oracle_extract"
N_FUZZ = 1000

def generate_random_utf16le_xored(length, key=42):
    # Generate a random string, encode to utf-16le, then xor
    # To avoid decode errors in oracle, we should generate valid surrogate pairs or just basic multilingual plane
    chars = "".join(random.choice(string.ascii_letters + string.digits + " \n\t") for _ in range(length // 2))
    utf16_bytes = chars.encode('utf-16le')
    # Pad if necessary to match length
    if len(utf16_bytes) < length:
        utf16_bytes += bytes([random.randint(0, 255) for _ in range(length - len(utf16_bytes))])
    elif len(utf16_bytes) > length:
        utf16_bytes = utf16_bytes[:length]
    return bytes(b ^ key for b in utf16_bytes)

def generate_fuzz_input():
    choice = random.random()
    if choice < 0.2:
        # Pure random bytes
        length = random.randint(0, 1024)
        return bytes([random.randint(0, 255) for _ in range(length)])

    # Generate semi-valid / valid archive
    num_files = random.randint(0, 10)
    data = bytearray()
    data.extend(struct.pack("<H", num_files))

    for _ in range(num_files):
        if len(data) > 1024:
            break

        # Filename
        name_len = random.randint(0, 50)
        name_choice = random.random()
        if name_choice < 0.2:
            name = "../" + "".join(random.choices(string.ascii_letters, k=max(0, name_len-3)))
        elif name_choice < 0.4:
            name = "/" + "".join(random.choices(string.ascii_letters, k=max(0, name_len-1)))
        else:
            name = "".join(random.choices(string.ascii_letters, k=name_len))

        name_bytes = name.encode('ascii', errors='ignore')[:name_len]
        name_len = len(name_bytes)

        data.append(name_len)
        data.extend(name_bytes)

        # Compressed data
        comp_len = random.randint(0, 200)
        comp_data = generate_random_utf16le_xored(comp_len)

        data.extend(struct.pack("<I", len(comp_data)))
        data.extend(comp_data)

    if choice < 0.5:
        # Truncate randomly
        if len(data) > 0:
            data = data[:random.randint(0, len(data))]

    return bytes(data)

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary not found at {ORACLE_BINARY}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "input.bin")
        lock_path = os.path.join(tmpdir, "lock.file")

        for i in range(N_FUZZ):
            test_data = generate_fuzz_input()
            with open(input_path, "wb") as f:
                f.write(test_data)

            # Randomly decide if we should hold the lock
            hold_lock = random.random() < 0.1

            lock_fd = None
            if hold_lock:
                # Create and lock the file
                lock_fd = open(lock_path, "w")
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            else:
                # Ensure lock file exists but is not locked
                open(lock_path, "w").close()

            try:
                # Run oracle
                oracle_proc = subprocess.run(
                    [ORACLE_BINARY, input_path, lock_path],
                    capture_output=True,
                    timeout=2
                )

                # Run agent
                agent_proc = subprocess.run(
                    ["python3", AGENT_SCRIPT, input_path, lock_path],
                    capture_output=True,
                    timeout=2
                )

                assert oracle_proc.stdout == agent_proc.stdout, (
                    f"Fuzz test {i} failed on stdout mismatch.\n"
                    f"Input length: {len(test_data)}\n"
                    f"Hold lock: {hold_lock}\n"
                    f"Oracle stdout: {oracle_proc.stdout!r}\n"
                    f"Agent stdout: {agent_proc.stdout!r}\n"
                )

                # We don't strictly assert stderr or exit code if the prompt only asks for stdout matching,
                # but it's good practice to ensure it didn't crash unexpectedly if oracle didn't.
                if oracle_proc.returncode == 0:
                    assert agent_proc.returncode == 0, f"Agent failed with code {agent_proc.returncode} but oracle succeeded. Stderr: {agent_proc.stderr!r}"

            finally:
                if lock_fd is not None:
                    fcntl.flock(lock_fd, fcntl.LOCK_UN)
                    lock_fd.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
