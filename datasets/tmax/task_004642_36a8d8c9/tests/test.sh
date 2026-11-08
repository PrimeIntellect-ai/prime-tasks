#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/query.py"
ORACLE_SCRIPT = "/tests/oracle.py"
TAGS_CSV = "/app/data/tags.csv"

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(TAGS_CSV), f"Tags CSV missing at {TAGS_CSV}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    # Extract tags
    tags = []
    with open(TAGS_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if "tag_name" in row:
                tags.append(row["tag_name"])

    assert tags, "No tags found in tags.csv"

    # Select 50 random tags
    random.seed(42)
    num_tests = min(50, len(tags))
    test_tags = random.sample(tags, num_tests)

    for tag in test_tags:
        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT, tag],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout.strip()

        # Run oracle supplied only at verification time
        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT, tag],
            capture_output=True,
            text=True
        )
        oracle_out = oracle_proc.stdout.strip()

        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch for tag '{tag}'.\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output: '{agent_out}'\n"
                f"Agent stderr: '{agent_proc.stderr}'"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
