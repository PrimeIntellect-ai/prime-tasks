#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import shutil
import pytest

ORACLE_PATH = "/app/xpak_pack"
AGENT_SCRIPT = "/home/user/xpak_pack.py"
N_ROUNDS = 50

def generate_random_file(path, is_ascii):
    size = random.randint(0, 16384)
    if is_ascii:
        # Printable ASCII (32-126) plus common whitespace like \n, \t
        chars = string.printable.encode('ascii')
        content = bytes(random.choice(chars) for _ in range(size))
    else:
        content = bytes(random.randint(0, 255) for _ in range(size))

    with open(path, "wb") as f:
        f.write(content)

@pytest.mark.parametrize("round_idx", range(N_ROUNDS))
def test_fuzz_equivalence(round_idx):
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42 + round_idx)

    num_files = random.randint(1, 8)

    with tempfile.TemporaryDirectory() as temp_dir:
        input_dir = os.path.join(temp_dir, "inputs")
        os.mkdir(input_dir)

        oracle_dir = os.path.join(temp_dir, "oracle")
        os.mkdir(oracle_dir)

        agent_dir = os.path.join(temp_dir, "agent")
        os.mkdir(agent_dir)

        input_files = []
        for _ in range(num_files):
            name_len = random.randint(5, 15)
            name = "".join(random.choice(string.ascii_letters + string.digits) for _ in range(name_len))
            file_path = os.path.join(input_dir, name)
            is_ascii = random.choice([True, False])
            generate_random_file(file_path, is_ascii)
            input_files.append(file_path)

        # Oracle run
        oracle_output = os.path.join(oracle_dir, "out.xpak")
        oracle_cmd = [ORACLE_PATH, oracle_output] + input_files
        try:
            subprocess.run(oracle_cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on round {round_idx}:\n{e.stderr}")

        # Agent run
        agent_output = os.path.join(agent_dir, "out.xpak")
        agent_cmd = ["python3", AGENT_SCRIPT, agent_output] + input_files
        try:
            subprocess.run(agent_cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent failed on round {round_idx}:\n{e.stderr}")

        # Compare .xpak
        assert os.path.exists(oracle_output), "Oracle did not produce .xpak"
        assert os.path.exists(agent_output), "Agent did not produce .xpak"

        with open(oracle_output, "rb") as f:
            oracle_xpak = f.read()
        with open(agent_output, "rb") as f:
            agent_xpak = f.read()

        if oracle_xpak != agent_xpak:
            pytest.fail(f".xpak mismatch on round {round_idx}. Oracle size: {len(oracle_xpak)}, Agent size: {len(agent_xpak)}")

        # Compare .manifest
        oracle_manifest = oracle_output + ".manifest"
        agent_manifest = agent_output + ".manifest"

        assert os.path.exists(oracle_manifest), "Oracle did not produce .manifest"
        assert os.path.exists(agent_manifest), "Agent did not produce .manifest"

        with open(oracle_manifest, "rb") as f:
            oracle_man = f.read()
        with open(agent_manifest, "rb") as f:
            agent_man = f.read()

        if oracle_man != agent_man:
            pytest.fail(f".manifest mismatch on round {round_idx}.\nOracle:\n{oracle_man.decode('utf-8', 'replace')}\nAgent:\n{agent_man.decode('utf-8', 'replace')}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
