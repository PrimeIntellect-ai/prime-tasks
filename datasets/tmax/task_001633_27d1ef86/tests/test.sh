#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import subprocess

import pytest

ORACLE_PATH = "/app/bin/oracle_parser"
AGENT_PATH = "/home/user/fast_parser_fixed"
SOURCE_PATH = "/home/user/fast_parser.cpp"
REGRESSION_PATH = "/home/user/regression_input.txt"
REBUILT_PATH = "/tmp/fast_parser_rebuilt"


def run_parser(path, test_input):
    return subprocess.run(
        [path],
        input=test_input,
        text=True,
        capture_output=True,
        timeout=5,
    )


def assert_equivalent(candidate, oracle, test_input):
    assert candidate.returncode == oracle.returncode, (
        f"Return code mismatch for {candidate.args[0]} on input: {test_input!r}\n"
        f"Oracle returned: {oracle.returncode}\n"
        f"Candidate returned: {candidate.returncode}\n"
        f"Candidate stderr: {candidate.stderr}"
    )
    assert candidate.stdout == oracle.stdout, (
        f"Stdout mismatch for {candidate.args[0]} on input: {test_input!r}\n"
        f"Oracle stdout: {oracle.stdout!r}\n"
        f"Candidate stdout: {candidate.stdout!r}"
    )


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Expected executable {AGENT_PATH} is missing. Did you compile your fixed code?"
    assert os.access(AGENT_PATH, os.X_OK), f"Expected {AGENT_PATH} to be executable."
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {AGENT_PATH} to be an ELF executable."

    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "The submitted executable must not be the oracle itself."
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), "The submitted executable is a byte-for-byte copy of the oracle."


def test_regression_input_transcribed():
    assert os.path.isfile(REGRESSION_PATH), f"Expected regression test {REGRESSION_PATH} is missing."
    with open(REGRESSION_PATH, "r", encoding="utf-8") as f:
        tokens = f.read().split()
    assert tokens == ["ADD", "15", "HEX", "1G", "MUL", "4", "END"], (
        "regression_input.txt does not contain the exact command sequence dictated in the audio report."
    )


def test_fixed_source_compiles():
    assert os.path.isfile(SOURCE_PATH), f"Expected fixed source {SOURCE_PATH} is missing."
    proc = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_PATH, "-o", REBUILT_PATH],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"The fixed source does not compile:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(REBUILT_PATH) and os.access(REBUILT_PATH, os.X_OK)


def generate_input():
    ops = []
    length = random.randint(0, 100)
    for _ in range(length):
        op_type = random.choice(['ADD', 'SUB', 'MUL', 'HEX', 'REV', 'END'])
        if op_type in ['ADD', 'SUB', 'MUL']:
            ops.append(f"{op_type} {random.randint(-1000, 1000)}")
        elif op_type == 'HEX':
            if random.random() < 0.5:
                ops.append(f"HEX {random.choice('0123456789ABCDEF')}{random.choice('0123456789ABCDEF')}")
            else:
                ops.append(f"HEX {random.choice('0123456789GHIJKLMNOPQRSTUVWXYZ')}{random.choice('0123456789GHIJKLMNOPQRSTUVWXYZ')}")
        else:
            ops.append(op_type)
    return " ".join(ops)


def test_regression_behavior():
    with open(REGRESSION_PATH, "r", encoding="utf-8") as f:
        test_input = f.read()
    oracle = run_parser(ORACLE_PATH, test_input)
    assert oracle.returncode == 0
    assert oracle.stdout == "60\n"
    assert_equivalent(run_parser(AGENT_PATH, test_input), oracle, test_input)
    assert_equivalent(run_parser(REBUILT_PATH, test_input), oracle, test_input)


@pytest.mark.parametrize("test_input", [
    "HEX 1G END",
    "HEX G1 END",
    "HEX 0 END",
    "HEX 000 END",
    "HEX ff END",
    "HEX aF REV END",
    "ADD 7 HEX ZZ MUL 3 END",
    "ADD 5 END MUL 99",
    "REV REV ADD -10 SUB -3 END",
    "ADD nope HEX FF END",
    "",
])
def test_directed_equivalence(test_input):
    oracle = run_parser(ORACLE_PATH, test_input)
    assert_equivalent(run_parser(AGENT_PATH, test_input), oracle, test_input)
    assert_equivalent(run_parser(REBUILT_PATH, test_input), oracle, test_input)


def test_fuzz_equivalence():
    random.seed(42)
    for _ in range(1000):
        test_input = generate_input()
        oracle_proc = run_parser(ORACLE_PATH, test_input)
        assert_equivalent(run_parser(AGENT_PATH, test_input), oracle_proc, test_input)
        assert_equivalent(run_parser(REBUILT_PATH, test_input), oracle_proc, test_input)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
