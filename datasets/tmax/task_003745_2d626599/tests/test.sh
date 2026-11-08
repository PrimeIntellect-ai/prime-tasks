#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import shutil
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/log_aggregator"
AGENT_PATH = "/home/user/solution.sh"
N_TESTS = 500


def generate_input(seed):
    random.seed(seed)
    num_lines = random.randint(10, 1000)
    lines = []
    for _ in range(num_lines):
        choice = random.random()
        if choice < 0.60:
            ts = "".join(random.choices(string.digits, k=10))
            lvl = "".join(random.choices(string.ascii_uppercase, k=random.randint(3, 8)))
            garbage1 = "".join(random.choices(string.ascii_letters, k=random.randint(0, 10)))
            garbage2 = "".join(random.choices(string.ascii_letters, k=random.randint(0, 10)))
            lines.append(f"{garbage1} ts={ts} {garbage2} lvl={lvl}")
        elif choice < 0.80:
            garbage1 = "".join(random.choices(string.ascii_letters, k=random.randint(0, 10)))
            garbage2 = "".join(random.choices(string.ascii_letters, k=random.randint(0, 10)))
            lines.append(f"{garbage1}TRACE{garbage2}")
        else:
            garbage = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(5, 20)))
            lines.append(garbage)
    return "\n".join(lines) + "\n"


def derived_output(input_data):
    entries = []
    for order, raw_line in enumerate(input_data.splitlines()):
        if "TRACE" in raw_line:
            continue
        ts_match = re.search(r"ts=([0-9]{10})", raw_line)
        lvl_match = re.search(r"lvl=([A-Z]+)", raw_line)
        ts_str = ts_match.group(1) if ts_match else "0000000000"
        lvl_str = lvl_match.group(1) if lvl_match and len(lvl_match.group(1)) < 31 else "INFO"
        entries.append((int(ts_str), order, ts_str, lvl_str, raw_line))
    entries.sort(key=lambda entry: (entry[0], entry[1]))
    return "".join(f"{ts_str}\t{lvl}\t{line}\n" for _, _, ts_str, lvl, line in entries)


def demote_to_user():
    user = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable: {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent solution missing: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent solution not executable: {AGENT_PATH}"

    with open(ORACLE_PATH, "rb") as oracle_file, open(AGENT_PATH, "rb") as agent_file:
        assert oracle_file.read() != agent_file.read(), "Agent solution is byte-identical to the oracle"

    cases = []
    for i in range(N_TESTS):
        input_data = generate_input(i)
        expected = derived_output(input_data)
        oracle_proc = subprocess.run(
            [ORACLE_PATH], input=input_data, text=True, capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i}\nError: {oracle_proc.stderr}"
        assert oracle_proc.stdout == expected, f"Oracle integrity check failed on test {i}"
        cases.append((i, input_data, expected))

    hidden_dir = tempfile.mkdtemp(prefix="verifier-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "log_aggregator")
    os.rename(ORACLE_PATH, hidden_oracle)

    try:
        for i, input_data, expected in cases:
            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=input_data,
                text=True,
                capture_output=True,
                cwd="/home/user",
                preexec_fn=demote_to_user,
            )
            assert agent_proc.returncode == 0, f"Agent failed on test {i}\nError: {agent_proc.stderr}"

            if expected != agent_proc.stdout:
                pytest.fail(
                    f"Mismatch on test {i}.\n"
                    f"--- Input ---\n{input_data[:500]}...\n"
                    f"--- Oracle Output ---\n{expected[:500]}...\n"
                    f"--- Agent Output ---\n{agent_proc.stdout[:500]}..."
                )
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(hidden_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
