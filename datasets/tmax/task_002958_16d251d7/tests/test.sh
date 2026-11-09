#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import struct
import bz2
import pytest


def generate_random_string(min_len=3, max_len=15):
    length = random.randint(min_len, max_len)
    chars = string.ascii_letters + string.digits + "_.-"
    return ''.join(random.choice(chars) for _ in range(length))


def generate_random_journal(num_entries=50):
    data = bytearray()
    expected_lines = []

    for _ in range(num_entries):
        opcode = random.choice([0, 1, 2])
        data.append(opcode)

        if opcode == 0:
            n = random.randint(1, 20)
            data.extend(struct.pack("<H", n))
            for _ in range(n):
                old_name = generate_random_string()
                new_name = generate_random_string()
                data.extend(old_name.encode('ascii') + b'\x00')
                data.extend(new_name.encode('ascii') + b'\x00')
                expected_lines.append(f"mv '{old_name}' '{new_name}'")
        elif opcode == 1:
            target = generate_random_string()
            link_name = generate_random_string()
            data.extend(target.encode('ascii') + b'\x00')
            data.extend(link_name.encode('ascii') + b'\x00')
            expected_lines.append(f"ln '{target}' '{link_name}'")
        elif opcode == 2:
            target = generate_random_string()
            link_name = generate_random_string()
            data.extend(target.encode('ascii') + b'\x00')
            data.extend(link_name.encode('ascii') + b'\x00')
            expected_lines.append(f"ln -s '{target}' '{link_name}'")

    expected = ''.join(line + '\n' for line in expected_lines)
    return bz2.compress(data), expected


def test_executable_exists():
    agent_exe = "/home/user/journal_compiler"
    assert os.path.isfile(agent_exe), f"Agent executable not found at {agent_exe}"
    assert os.access(agent_exe, os.X_OK), f"Agent file at {agent_exe} is not executable"


def test_fuzz_equivalence():
    agent_exe = "/home/user/journal_compiler"
    random.seed(42)

    for i in range(100):
        compressed_journal, expected_out = generate_random_journal(
            num_entries=random.randint(10, 100)
        )

        agent_proc = subprocess.run(
            [agent_exe],
            input=compressed_journal,
            capture_output=True,
            timeout=5
        )

        assert agent_proc.returncode == 0, (
            f"Agent program failed (return code {agent_proc.returncode}) "
            f"on fuzz input {i}"
        )

        agent_out = agent_proc.stdout.decode('utf-8', errors='replace')

        if expected_out != agent_out:
            pytest.fail(
                f"Output mismatch on fuzz input {i}.\n"
                f"--- Expected Output ---\n{expected_out}\n"
                f"--- Agent Output ---\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
