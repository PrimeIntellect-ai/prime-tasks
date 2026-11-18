#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/resolve.py"
ORACLE_BINARY = "/tests/oracle_resolver"
N_TESTS = 100

def generate_random_semver():
    major = random.randint(0, 4)
    minor = random.randint(0, 9)
    patch = random.randint(0, 9)
    base = f"{major}.{minor}.{patch}"
    if random.random() < 0.2:
        rc = random.randint(1, 5)
        base += f"-rc{rc}"
    return base

def generate_random_db(num_nodes):
    names = [f"lib{c}" for c in string.ascii_uppercase] + ["libCore", "libNet", "libMath", "libUtils"]
    abis = ["sysv", "elf-v2", "cxx11", "msvc"]
    meta_choices = ["stable", "experimental", "deprecated", "fast"]

    db = []
    available_names = set()

    for _ in range(num_nodes):
        name = random.choice(names)
        version = generate_random_semver()
        abi = random.choice(abis)

        num_meta = random.randint(0, len(meta_choices))
        metadata = random.sample(meta_choices, num_meta)

        # Pick 0 to 3 random dependencies from already generated names to avoid pure cycles,
        # or just pick randomly from all names to allow cycles. The prompt says "complex resolution graphs".
        # Let's pick randomly from all names.
        num_deps = random.randint(0, 3)
        deps = random.sample(names, min(num_deps, len(names)))

        db.append({
            "name": name,
            "version": version,
            "abi": abi,
            "metadata": metadata,
            "deps": deps
        })
        available_names.add(name)

    target = random.choice(list(available_names))
    return db, target

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"

def test_agent_matches_oracle():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary not found at {ORACLE_BINARY}"

    random.seed(42)

    for i in range(N_TESTS):
        num_nodes = random.randint(20, 50)
        db, target = generate_random_db(num_nodes)

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(db, f)
            db_path = f.name

        try:
            oracle_cmd = ["python3", ORACLE_BINARY, "--db", db_path, "--target", target]
            agent_cmd = ["python3", AGENT_SCRIPT, "--db", db_path, "--target", target]

            oracle_code, oracle_out, oracle_err = run_cmd(oracle_cmd)
            agent_code, agent_out, agent_err = run_cmd(agent_cmd)

            assert agent_code == oracle_code, (
                f"Fuzz test {i+1} failed: Return code mismatch.\n"
                f"Target: {target}\n"
                f"Oracle return code: {oracle_code}\n"
                f"Agent return code: {agent_code}\n"
                f"Oracle stderr: {oracle_err}\n"
                f"Agent stderr: {agent_err}\n"
                f"Input DB: {json.dumps(db, indent=2)}"
            )

            assert agent_out == oracle_out, (
                f"Fuzz test {i+1} failed: Output mismatch.\n"
                f"Target: {target}\n"
                f"Oracle output:\n{oracle_out}\n"
                f"Agent output:\n{agent_out}\n"
                f"Input DB: {json.dumps(db, indent=2)}"
            )
        finally:
            os.remove(db_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
