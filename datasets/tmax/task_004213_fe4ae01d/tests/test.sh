#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import sys
import pytest

ORACLE_PATH = "/tests/oracle.py"
AGENT_PATH = "/home/user/apply_config.sh"


def generate_random_changelog(num_lines):
    # Begin with guaranteed stateful operations so MOD and DEL behavior,
    # including operations on existing and missing keys, is always exercised.
    lines = [
        "ADD Network Host seed",
        "MOD Network Host changed",
        "DEL Network Host",
        "MOD Network Host ignored",
        "MOD Core Version 2.0",
        "DEL Modules Auth",
        "ADD Empty Only value",
        "DEL Empty Only",
    ]

    sections = ["Core", "Modules", "Network", "System", "DB"]
    keys = ["Version", "Auth", "Host", "Port", "User", "Pass", "Timeout", "Retry"]

    while len(lines) < num_lines:
        cmd = random.choice(["ADD", "MOD", "DEL"])
        # Reuse a finite set of section/key pairs so later commands frequently
        # operate on state established by earlier commands.
        sec = random.choice(sections)
        key = random.choice(keys)
        val = "".join(random.choices(string.ascii_letters + string.digits, k=6))

        if cmd == "ADD":
            lines.append(f"ADD {sec} {key} {val}")
        elif cmd == "MOD":
            lines.append(f"MOD {sec} {key} {val}")
        else:
            lines.append(f"DEL {sec} {key}")

    return "\n".join(lines[:num_lines]) + "\n"


def build_cases_and_expected():
    assert os.path.exists(ORACLE_PATH), "Oracle implementation missing from tests"

    cases = [
        "ADD Network Host alpha\nMOD Network Host beta\nDEL Network Host\n",
        "MOD Core Version 9.9\nDEL Modules Auth\nMOD Missing Key ignored\nDEL Missing Key\n",
        "ADD Zed B 2\nADD Zed A 1\nADD Alpha Z 3\nDEL Zed B\n",
        "ADD Empty Gone x\nDEL Empty Gone\nMOD Empty Gone ignored\n",
    ]

    random.seed(42)
    for _ in range(100):
        cases.append(generate_random_changelog(random.randint(10, 100)))

    expected = []
    for i, changelog in enumerate(cases):
        proc = subprocess.run(
            [sys.executable, ORACLE_PATH],
            input=changelog,
            text=True,
            capture_output=True,
        )
        assert proc.returncode == 0, f"Oracle failed while preparing case {i}: {proc.stderr}"
        expected.append(proc.stdout)

    # The submitted artifact must not be able to call the oracle while tested.
    os.remove(ORACLE_PATH)
    return cases, expected


CASES, EXPECTED = build_cases_and_expected()


def test_base_ini_recovered():
    base_ini_path = "/home/user/base.ini"
    assert os.path.exists(base_ini_path), "base.ini was not found at /home/user/base.ini"

    with open(base_ini_path, "r") as f:
        content = f.read().strip()

    expected_content = "[Core]\nVersion=1.0\n[Modules]\nAuth=true"
    assert content == expected_content, f"Content of base.ini is incorrect. Got:\n{content}"


def test_script_exists_and_no_prohibited_interpreters():
    assert os.path.exists(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"

    with open(AGENT_PATH, "r") as f:
        content = f.read().lower()

    for interpreter in ["python", "perl", "ruby", "node"]:
        assert interpreter not in content, f"Script contains prohibited interpreter: {interpreter}"


def test_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), "Agent script missing"

    for i, (changelog, expected) in enumerate(zip(CASES, EXPECTED)):
        agent_proc = subprocess.run(
            ["bash", AGENT_PATH],
            input=changelog,
            text=True,
            capture_output=True,
        )

        assert agent_proc.returncode == 0, (
            f"Agent script failed on test {i}\nInput:\n{changelog}"
            f"\nStderr:\n{agent_proc.stderr}"
        )
        if agent_proc.stdout != expected:
            pytest.fail(
                f"Mismatch on test {i}!\n"
                f"Input Changelog:\n{changelog}\n"
                f"Oracle Output:\n{expected}\n"
                f"Agent Output:\n{agent_proc.stdout}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
