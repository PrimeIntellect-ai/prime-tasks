#!/bin/bash
set -e
mkdir -p /logs/verifier

# The oracle is uploaded only after the agent has finished. Keep it root-only so
# an agent artifact cannot defer to, wrap, or symlink to it during verification.
chmod 700 /tests/oracle_compress

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import subprocess
import random
import string
import pytest

AGENT_PATH = "/home/user/compress_rotate"
ORACLE_PATH = "/tests/oracle_compress"
AGENT_USER = pwd.getpwnam("user")

def demote_to_agent_user():
    os.setgroups([])
    os.setgid(AGENT_USER.pw_gid)
    os.setuid(AGENT_USER.pw_uid)

def test_agent_executable_exists():
    """Verify that the agent's compressor executable exists and is executable."""
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable"

def test_oracle_exists():
    """Verify that the verification-only oracle exists and is executable."""
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle file at {ORACLE_PATH} is not executable"

def generate_test_cases():
    """Generate 500 test cases based on the fuzz distribution and edge cases."""
    random.seed(42)
    cases = []

    cases.append("")
    cases.append("^" * 5000)
    cases.append("a" * 5000)
    cases.append("a^" * 2500)
    cases.append("^^" * 2500)

    for c in ['a', '^']:
        for i in range(1, 10):
            cases.append(c * i)

    chars = string.printable

    for _ in range(477):
        length = random.randint(0, 10000)
        parts = []
        curr = 0
        while curr < length:
            r = random.random()
            if r < 0.2:
                l = random.randint(1, 15)
                parts.append('^' * l)
                curr += l
            elif r < 0.5:
                c = random.choice(chars)
                l = random.randint(1, 15)
                parts.append(c * l)
                curr += l
            else:
                l = random.randint(1, 50)
                parts.append(''.join(random.choices(chars, k=l)))
                curr += l
        cases.append("".join(parts)[:length])

    return cases

@pytest.mark.parametrize("input_data", generate_test_cases())
def test_fuzz_equivalence(input_data):
    """Run both programs on random inputs and assert exact equivalence."""
    if not os.path.isfile(AGENT_PATH) or not os.access(AGENT_PATH, os.X_OK):
        pytest.fail(f"Agent executable not found or not executable at {AGENT_PATH}")

    input_bytes = input_data.encode('utf-8')

    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr.decode('utf-8', errors='replace')}"

    try:
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            preexec_fn=demote_to_agent_user
        )
    except PermissionError as exc:
        pytest.fail(f"Agent executable could not be run by user: {exc}")

    assert agent_proc.returncode == 0, f"Agent failed: {agent_proc.stderr.decode('utf-8', errors='replace')}"

    if oracle_proc.stdout != agent_proc.stdout:
        in_str = input_data if len(input_data) < 100 else input_data[:100] + "... (truncated)"
        or_str = oracle_proc.stdout.decode('utf-8', errors='replace')
        or_str = or_str if len(or_str) < 100 else or_str[:100] + "... (truncated)"
        ag_str = agent_proc.stdout.decode('utf-8', errors='replace')
        ag_str = ag_str if len(ag_str) < 100 else ag_str[:100] + "... (truncated)"

        pytest.fail(
            f"Output mismatch!\n"
            f"Input: {repr(in_str)}\n"
            f"Expected (Oracle): {repr(or_str)}\n"
            f"Got (Agent): {repr(ag_str)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
