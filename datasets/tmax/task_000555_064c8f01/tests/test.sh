#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile
import struct
import pytest

ORACLE_PATH = "/tests/oracle_bin_parser"
AGENT_PATH = "/home/user/parser"

def generate_random_bytes(length):
    return bytes(random.getrandbits(8) for _ in range(length))

def generate_fuzz_files(num_files, dest_dir):
    random.seed(42)
    file_paths = []

    for i in range(num_files):
        path = os.path.join(dest_dir, f"fuzz_{i}.bin")
        is_structured = random.random() < 0.8

        if not is_structured:
            length = random.randint(0, 1024)
            data = generate_random_bytes(length)
        else:
            magic = b"ARTF"
            version = b"\x02"
            flags = bytes([random.randint(0, 255)])
            k_len = random.randint(0, 255)
            k_len_byte = bytes([k_len])
            emb_key = generate_random_bytes(k_len)

            # 50% chance to have a correct payload length, 50% chance to have an incorrect one
            actual_p_len = random.randint(0, 500)
            if random.random() < 0.5:
                claimed_p_len = actual_p_len
            else:
                claimed_p_len = random.randint(0, 1000)

            p_len_bytes = struct.pack("<I", claimed_p_len)
            payload = generate_random_bytes(actual_p_len)

            # sometimes truncate the header
            if random.random() < 0.05:
                data = (magic + version + flags + k_len_byte + emb_key + p_len_bytes + payload)[:random.randint(0, 10)]
            else:
                data = magic + version + flags + k_len_byte + emb_key + p_len_bytes + payload

        with open(path, "wb") as f:
            f.write(data)
        file_paths.append(path)

    return file_paths

def test_parser_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent program not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle program at {ORACLE_PATH} is not executable"

    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent program must not be a byte-identical copy of the oracle"

    with tempfile.TemporaryDirectory() as tmpdir:
        # Generate 1000 files to keep test time reasonable while maintaining good coverage
        fuzz_files = generate_fuzz_files(1000, tmpdir)

        for fpath in fuzz_files:
            # Run oracle
            oracle_res = subprocess.run(
                [ORACLE_PATH, fpath],
                capture_output=True
            )

            # Run agent
            agent_res = subprocess.run(
                [AGENT_PATH, fpath],
                capture_output=True
            )

            assert oracle_res.returncode == agent_res.returncode, (
                f"Return code mismatch on input {fpath}.\n"
                f"Oracle exit: {oracle_res.returncode}\n"
                f"Agent exit: {agent_res.returncode}\n"
                f"Oracle stdout: {oracle_res.stdout!r}\n"
                f"Agent stdout: {agent_res.stdout!r}"
            )

            assert oracle_res.stdout == agent_res.stdout, (
                f"Stdout mismatch on input {fpath}.\n"
                f"Oracle stdout: {oracle_res.stdout!r}\n"
                f"Agent stdout: {agent_res.stdout!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
