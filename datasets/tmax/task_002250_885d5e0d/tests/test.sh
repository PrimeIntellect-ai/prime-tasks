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
import pytest

ORACLE_PATH = "/app/oracle_processor"
AGENT_PATH = "/home/user/pr_review/process_audio.sh"
N_FUZZ = 1000  # Using 1000 to ensure tests run within reasonable time limits

def generate_fuzz_input(seed):
    random.seed(seed)
    target_length = random.randint(50, 5000)
    tags = ["[MUSIC]", "[APPLAUSE]", "[SPEECH]", "[NOISE]", "[MALFORMED", "NO_BRACKET]", "[   ]", "[]"]
    lines = []
    current_length = 0

    while current_length < target_length:
        h = random.randint(0, 23)
        m = random.randint(0, 59)
        s = random.randint(0, 59)
        ms = random.randint(0, 999)
        tag = random.choice(tags)
        text_len = random.randint(5, 50)
        text = ''.join(random.choices(string.ascii_letters + " ", k=text_len))
        line = f"[{h:02d}:{m:02d}:{s:02d}.{ms:03d}] {tag} {text}\n"
        lines.append(line)
        current_length += len(line)

    return "".join(lines)[:target_length]

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program missing: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle program not executable: {ORACLE_PATH}"

    assert os.path.isfile(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script not executable: {AGENT_PATH}"

    with tempfile.TemporaryDirectory() as tmpdir:
        input_file = os.path.join(tmpdir, "fuzz_input.txt")

        for i in range(N_FUZZ):
            inp_data = generate_fuzz_input(42 + i)
            with open(input_file, "w", encoding="utf-8") as f:
                f.write(inp_data)

            oracle_proc = subprocess.run([ORACLE_PATH, input_file], capture_output=True, text=True)
            agent_proc = subprocess.run([AGENT_PATH, input_file], capture_output=True, text=True)

            # Check for exact stdout match
            if oracle_proc.stdout != agent_proc.stdout:
                error_msg = (
                    f"Stdout mismatch on fuzz iteration {i}.\n\n"
                    f"--- INPUT ---\n{inp_data}\n\n"
                    f"--- ORACLE STDOUT ---\n{oracle_proc.stdout}\n\n"
                    f"--- AGENT STDOUT ---\n{agent_proc.stdout}\n"
                )
                pytest.fail(error_msg)

            # Also ensure return codes match (optional but good practice)
            if oracle_proc.returncode != agent_proc.returncode:
                error_msg = (
                    f"Return code mismatch on fuzz iteration {i}. "
                    f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}\n\n"
                    f"--- INPUT ---\n{inp_data}\n"
                )
                pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
