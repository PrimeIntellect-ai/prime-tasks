#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sys
import struct
import random
import string
import subprocess
import tempfile
import pytest

ORACLE_BIN = "/app/legacy_extract"
AGENT_SCRIPT = "/home/user/extract.py"
NUM_ITERATIONS = 50

def generate_arc(path, num_files, dup_prob=0.3):
    files = []
    with open(path, 'wb') as f:
        f.write(b'ARC1')
        f.write(struct.pack('<I', num_files))

        for _ in range(num_files):
            if files and random.random() < dup_prob:
                orig = random.choice(files)
                content = orig['content']
            else:
                size = random.randint(0, 10240)
                content = os.urandom(size)

            name_len = random.randint(5, 20)
            ext = random.choice(['.txt', '.dat'])
            name = ''.join(random.choices(string.ascii_letters + string.digits, k=name_len)) + ext

            files.append({'name': name, 'content': content})

            f.write(struct.pack('<H', len(name)))
            f.write(name.encode('ascii'))
            f.write(struct.pack('<I', len(content)))
            f.write(content)

def get_dir_state(dir_path):
    state = {}
    for root, _, files in os.walk(dir_path):
        for f in files:
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, dir_path)
            stat = os.stat(full_path)
            with open(full_path, 'rb') as fp:
                content = fp.read()
            state[rel_path] = {
                'inode': stat.st_ino,
                'content': content
            }
    return state

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary missing at {ORACLE_BIN}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42)

    for i in range(NUM_ITERATIONS):
        num_files = random.randint(0, 50)

        with tempfile.TemporaryDirectory() as oracle_dir, \
             tempfile.TemporaryDirectory() as agent_dir, \
             tempfile.TemporaryDirectory() as arc_dir:

            arc_path = os.path.join(arc_dir, f"test_{i}.arc")
            generate_arc(arc_path, num_files)

            oracle_proc = subprocess.run(
                [ORACLE_BIN, arc_path],
                cwd=oracle_dir,
                capture_output=True,
                text=True
            )

            agent_proc = subprocess.run(
                [sys.executable, AGENT_SCRIPT, arc_path],
                cwd=agent_dir,
                capture_output=True,
                text=True
            )

            assert agent_proc.returncode == oracle_proc.returncode, \
                f"Iteration {i}: Return code mismatch. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

            oracle_output = json.loads(oracle_proc.stdout)
            oracle_output['manifest'] = sorted(
                oracle_output['manifest'], key=lambda entry: entry['path']
            )
            expected_stdout = json.dumps(oracle_output, indent=2)

            assert agent_proc.stdout == expected_stdout, \
                f"Iteration {i}: stdout mismatch.\nExpected sorted stdout:\n{expected_stdout}\nAgent stdout:\n{agent_proc.stdout}"

            oracle_state = get_dir_state(oracle_dir)
            agent_state = get_dir_state(agent_dir)

            assert set(oracle_state.keys()) == set(agent_state.keys()), \
                f"Iteration {i}: Extracted files mismatch. Oracle: {list(oracle_state.keys())}, Agent: {list(agent_state.keys())}"

            oracle_inodes = {}
            agent_inodes = {}

            for path in oracle_state:
                assert oracle_state[path]['content'] == agent_state[path]['content'], \
                    f"Iteration {i}: Content mismatch for file {path}"

                o_ino = oracle_state[path]['inode']
                a_ino = agent_state[path]['inode']

                if o_ino not in oracle_inodes:
                    oracle_inodes[o_ino] = []
                oracle_inodes[o_ino].append(path)

                if a_ino not in agent_inodes:
                    agent_inodes[a_ino] = []
                agent_inodes[a_ino].append(path)

            oracle_link_groups = sorted([sorted(group) for group in oracle_inodes.values()])
            agent_link_groups = sorted([sorted(group) for group in agent_inodes.values()])

            assert oracle_link_groups == agent_link_groups, \
                f"Iteration {i}: Hardlink structure mismatch.\nOracle link groups: {oracle_link_groups}\nAgent link groups: {agent_link_groups}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
