#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

AGENT_BIN = "/home/user/relevance"
AGENT_SRC = "/home/user/relevance.cpp"
ORACLE_BIN = "/tests/oracle_relevance"


def expected_score(input_str):
    weights = {"anomaly": 5, "dataset": 3, "clean": 4, "null": 2}
    tokens = re.findall(r"[A-Za-z0-9]+", input_str.lower())
    return sum(weights.get(token, 0) for token in tokens if len(token) >= 4) * 7


def run_agent(input_str):
    return subprocess.run(
        [AGENT_BIN, input_str],
        capture_output=True,
        text=True,
        timeout=5,
    )


def test_required_artifacts():
    assert os.path.isfile(AGENT_SRC), f"C++ source not found at {AGENT_SRC}"
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent executable is not a compiled ELF binary"

    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary at {ORACLE_BIN} is not executable"


def test_directed_relevance_cases():
    cases = [
        "",
        "!!! --- ___",
        "clean",
        "CLEAN",
        "clean clean",
        "anomaly,dataset;clean/null",
        "ANOMALY Dataset ClEaN NuLl",
        "abc null xyz",
        "null-null-null",
        "cleanliness anomalous datasets nullable",
        "clean123 clean_123 clean.clean",
        "prefixclean clean suffixnull null",
        "a!b@c#null$dataset%anomaly^clean",
    ]

    for input_str in cases:
        proc = run_agent(input_str)
        expected = f"{expected_score(input_str)}\n"
        assert proc.returncode == 0, f"Nonzero exit for {input_str!r}: {proc.returncode}"
        assert proc.stderr == "", f"Unexpected stderr for {input_str!r}: {proc.stderr!r}"
        assert proc.stdout == expected, (
            f"Wrong output for {input_str!r}: expected {expected!r}, got {proc.stdout!r}"
        )


def test_relevance_fuzz_equivalence():
    random.seed(42)
    chars = [chr(i) for i in range(32, 127)]

    for i in range(500):
        length = random.randint(0, 200)
        input_str = "".join(random.choice(chars) for _ in range(length))

        oracle_proc = subprocess.run(
            [ORACLE_BIN, input_str],
            capture_output=True,
            text=True,
            timeout=5,
        )
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [AGENT_BIN, input_str],
            capture_output=True,
            text=True,
            timeout=5,
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_proc.returncode == 0
        assert agent_proc.returncode == 0
        assert agent_out == oracle_out, (
            f"Mismatch on iteration {i}.\n"
            f"Input: {input_str!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
