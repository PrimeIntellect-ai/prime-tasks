#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest


def test_directory_created():
    expected_dir = "/home/user/loop_archive_8891f"
    assert os.path.isdir(expected_dir), f"The expected directory '{expected_dir}' was not created. Did you correctly extract the path from the video?"


def generate_random_hex(length):
    return ''.join(random.choices(string.hexdigits.lower(), k=length))


def generate_random_path():
    length = random.randint(4, 8)
    name = ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))
    return f"/test/{name}"


def generate_manifest():
    num_lines = random.randint(10, 500)

    filepaths = []
    for _ in range(num_lines):
        filepaths.append(generate_random_path())

    filepaths = list(set(filepaths))
    lines = []
    for filepath in filepaths:
        is_symlink = random.random() < 0.7
        if is_symlink:
            if random.random() < 0.9 and filepaths:
                target = random.choice(filepaths)
            else:
                target = generate_random_path()
            lines.append(f"{filepath}|S|{target}")
        else:
            hash_val = generate_random_hex(64)
            lines.append(f"{filepath}|F|{hash_val}")

    return "\n".join(lines) + "\n"


def reference_output(manifest):
    nodes = {}
    for line in manifest.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split('|')
        if len(parts) == 3:
            nodes[parts[0]] = (parts[1], parts[2])

    results = []
    for start_node in nodes:
        visited = set()
        curr = start_node
        while True:
            if curr in visited:
                results.append(f"{start_node}|BROKEN")
                break
            visited.add(curr)
            if curr not in nodes:
                results.append(f"{start_node}|BROKEN")
                break
            ntype, nval = nodes[curr]
            if ntype == 'F':
                results.append(f"{start_node}|RESOLVED|{nval}")
                break
            if ntype == 'S':
                curr = nval
            else:
                results.append(f"{start_node}|BROKEN")
                break

    results.sort()
    return ''.join(f"{result}\n" for result in results)


def test_fuzz_equivalence():
    agent_script = "/home/user/safe_manifest_parser.sh"
    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"

    random.seed(42)

    for i in range(100):
        manifest = generate_manifest()
        oracle_out = reference_output(manifest)

        agent_proc = subprocess.run(
            ["bash", agent_script],
            input=manifest,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout

        if agent_out != oracle_out:
            error_msg = (
                f"Mismatch on iteration {i}!\n\n"
                f"--- Input Manifest ---\n{manifest}\n"
                f"--- Expected Output (Oracle) ---\n{oracle_out}\n"
                f"--- Actual Output (Agent) ---\n{agent_out}\n"
                f"STDERR: {agent_proc.stderr}"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
