#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/tests/generate_auth_oracle.sh"
AGENT_PATH = "/home/user/generate_auth.sh"
EXTRACTOR_PATH = "/app/cookie-extractor-1.0/cookie-extractor"
EXTRACTOR_DIR = "/app/cookie-extractor-1.0"

def test_extractor_executable_exists():
    assert os.path.isfile(EXTRACTOR_PATH), f"Executable {EXTRACTOR_PATH} does not exist. Did you run make?"
    assert os.access(EXTRACTOR_PATH, os.X_OK), f"File {EXTRACTOR_PATH} is not executable."

def test_makefile_rebuilds_extractor():
    os.remove(EXTRACTOR_PATH)
    proc = subprocess.run(
        ["make"],
        cwd=EXTRACTOR_DIR,
        text=True,
        capture_output=True,
        check=False,
    )
    assert proc.returncode == 0, f"make failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert os.path.isfile(EXTRACTOR_PATH), "make did not produce cookie-extractor"
    assert os.access(EXTRACTOR_PATH, os.X_OK), "make produced a non-executable cookie-extractor"

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Script {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Script {AGENT_PATH} is not executable."

def generate_random_cookie():
    cmd_len = random.randint(1, 15)
    cmd = "".join(random.choice(string.printable[:95]) for _ in range(cmd_len))
    encrypted_hex = "".join(f"{ord(c) ^ 0x5A:02x}" for c in cmd)

    def rand_kv():
        k = "".join(random.choices(string.ascii_lowercase, k=random.randint(3, 8)))
        v = "".join(random.choices(string.ascii_lowercase + string.digits, k=random.randint(3, 8)))
        return f"{k}={v}"

    prefix_count = random.randint(0, 3)
    suffix_count = random.randint(0, 3)
    prefix = "".join(f"{rand_kv()}; " for _ in range(prefix_count))
    suffix_parts = [rand_kv() for _ in range(suffix_count)]
    suffix = "; " + "; ".join(suffix_parts) if suffix_parts else ""
    return f"Cookie: {prefix}CommandToken={encrypted_hex}{suffix}"

def test_fuzz_equivalence():
    random.seed(42)
    N = 100

    for i in range(N):
        cookie = generate_random_cookie()

        oracle_proc = subprocess.run(
            ["bash", ORACLE_PATH],
            input=cookie,
            text=True,
            capture_output=True,
            check=False,
        )
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=cookie,
            text=True,
            capture_output=True,
            check=False,
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent script failed with return code {agent_proc.returncode} on input: {cookie}\nStderr: {agent_proc.stderr}"
        assert agent_out == oracle_out, (
            f"Mismatch on input {i+1}/{N}:\n"
            f"Input: {cookie}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
