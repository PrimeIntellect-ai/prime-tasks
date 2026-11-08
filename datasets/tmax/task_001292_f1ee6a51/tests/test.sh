#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess

AGENT_SCRIPT = "/home/user/fstab_linter.py"
ORACLE_SCRIPT = "/tests/oracle.py"

def generate_fstab_inputs(num_inputs=500, seed=42):
    random.seed(seed)
    inputs = []

    filesystems = ['ext4', 'xfs', 'vfat', 'ntfs', 'btrfs']
    base_options = ['defaults', 'ro', 'rw', 'noatime', 'nodiratime', 'relatime', 'user', 'nouser', 'sync', 'async']

    for _ in range(num_inputs):
        r = random.random()
        if r < 0.20:
            comment_text = ''.join(random.choices(string.ascii_letters + string.digits + " \t", k=random.randint(5, 30)))
            ws_before = " " * random.randint(0, 3)
            inputs.append(f"{ws_before}#{comment_text}")
        elif r < 0.30:
            ws_chars = [' ', '\t']
            inputs.append(''.join(random.choices(ws_chars, k=random.randint(0, 10))))
        else:
            num_fields = random.randint(4, 6)

            f1 = f"UUID={random.randint(1000, 9999)}-{random.randint(1000, 9999)}" if random.choice([True, False]) else f"/dev/sd{random.choice('abcdef')}{random.randint(1,4)}"
            f2 = random.choice(['/', '/boot', '/home', '/var', '/usr', '/mnt/data'])
            f3 = random.choice(filesystems)

            opts = random.sample(base_options, random.randint(1, 3))
            if f3 == 'ext4' and random.random() < 0.3:
                opts.append('errors=remount-ro')
            f4 = ','.join(opts)

            fields = [f1, f2, f3, f4]
            if num_fields >= 5:
                fields.append(str(random.randint(0, 1)))
            if num_fields == 6:
                fields.append(str(random.randint(0, 2)))

            line = ""
            for i, field in enumerate(fields):
                line += field
                if i < len(fields) - 1:
                    line += ''.join(random.choices([' ', '\t'], k=random.randint(1, 4)))

            line = (''.join(random.choices([' ', '\t'], k=random.randint(0, 3))) +
                    line +
                    ''.join(random.choices([' ', '\t'], k=random.randint(0, 3))))
            inputs.append(line)

    return inputs

def test_fstab_linter_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    inputs = generate_fstab_inputs(500, seed=1337)

    for i, inp in enumerate(inputs):
        oracle_proc = subprocess.run(
            ['python3', ORACLE_SCRIPT, inp],
            capture_output=True,
            text=True
        )
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            ['python3', AGENT_SCRIPT, inp],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout

        assert oracle_out == agent_out, (
            f"Mismatch on input {i}:\n"
            f"Input string : {repr(inp)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output : {repr(agent_out)}\n"
            f"Agent stderr : {agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
