#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod +x /tests/oracle_extractor

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

AGENT_EXECUTABLE = "/home/user/extractor"
ORACLE_EXECUTABLE = "/tests/oracle_extractor"

def test_agent_executable_exists():
    assert os.path.exists(AGENT_EXECUTABLE), f"Agent executable missing at {AGENT_EXECUTABLE}. Did you compile your C++ code?"
    assert os.path.isfile(AGENT_EXECUTABLE), f"Path {AGENT_EXECUTABLE} is not a file."
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable {AGENT_EXECUTABLE} is not executable."

def test_agent_is_not_oracle_copy():
    assert os.path.exists(ORACLE_EXECUTABLE), f"Oracle executable missing at {ORACLE_EXECUTABLE}. Test setup issue."
    with open(AGENT_EXECUTABLE, "rb") as agent_file, open(ORACLE_EXECUTABLE, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent executable must not be a byte-identical copy of the reference executable."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_EXECUTABLE), f"Oracle executable missing at {ORACLE_EXECUTABLE}. Test setup issue."

    random.seed(42)
    # N = 20 random integers chosen uniformly between 1 and 30
    test_inputs = [random.randint(1, 30) for _ in range(20)]

    for t in test_inputs:
        cmd_oracle = [ORACLE_EXECUTABLE, str(t)]
        cmd_agent = [AGENT_EXECUTABLE, str(t)]

        try:
            res_oracle = subprocess.run(cmd_oracle, capture_output=True, text=True, check=True, timeout=15)
            out_oracle = res_oracle.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {t}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {t}")

        try:
            res_agent = subprocess.run(cmd_agent, capture_output=True, text=True, check=True, timeout=15)
            out_agent = res_agent.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on input {t} (exit code {e.returncode}). Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input {t}")

        assert out_agent == out_oracle, (
            f"Output mismatch on input {t}.\n"
            f"Expected (Oracle): {out_oracle!r}\n"
            f"Got (Agent):       {out_agent!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
