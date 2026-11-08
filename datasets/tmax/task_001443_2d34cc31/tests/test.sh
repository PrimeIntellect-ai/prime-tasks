#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import pwd
import random
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/oracle_calc"
AGENT_PATH = "/home/user/solution.py"


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def test_solution_exists():
    assert os.path.isfile(AGENT_PATH), "Solution file /home/user/solution.py does not exist."


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent solution missing at {AGENT_PATH}"

    # Reject an unchanged copy of the reference executable placed in the agent's
    # writable area as a helper program.
    oracle_hash = file_hash(ORACLE_PATH)
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            if path == AGENT_PATH or path == "/home/user/dev_drive.img":
                continue
            try:
                if os.path.getsize(path) == os.path.getsize(ORACLE_PATH) and file_hash(path) == oracle_hash:
                    pytest.fail(f"Found a byte-identical copy of the oracle at {path}")
            except (OSError, PermissionError):
                pass

    random.seed(42)
    # Fuzz-input distribution: N=1000, uniform [0.0, 1e15]
    inputs = [random.uniform(0.0, 1e15) for _ in range(1000)]
    inputs.extend([0.0, 1.0, 1e12, 1e15])

    # Preserve the original oracle equivalence check, while also deriving the
    # expected values independently from the recovered mathematical function.
    expected = []
    for val in inputs:
        str_val = str(val)
        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH, str_val], capture_output=True, text=True,
                check=True, timeout=2
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {str_val}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {str_val}")

        oracle_out = oracle_res.stdout.strip()
        derived_out = f"{1.0 / (math.sqrt(val + 1.0) + math.sqrt(val)):.15f}"
        assert oracle_out == derived_out, (
            f"Reference/derived mismatch on input {str_val}: "
            f"'{oracle_out}' != '{derived_out}'"
        )
        expected.append(oracle_out)

    # Make the reference executable unavailable while submissions are running.
    # The agent is also run unprivileged so it cannot inspect the root-only
    # temporary location.
    hidden_dir = tempfile.mkdtemp(prefix="verifier-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle_calc")
    os.rename(ORACLE_PATH, hidden_oracle)

    nobody = pwd.getpwnam("nobody")

    def demote():
        os.setgroups([])
        os.setgid(nobody.pw_gid)
        os.setuid(nobody.pw_uid)

    try:
        for val, oracle_out in zip(inputs, expected):
            str_val = str(val)
            try:
                agent_res = subprocess.run(
                    ["python3", AGENT_PATH, str_val],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=2,
                    cwd="/tmp",
                    preexec_fn=demote,
                )
                agent_out = agent_res.stdout.strip()
            except subprocess.CalledProcessError as e:
                pytest.fail(
                    f"Agent solution failed on input {str_val}:\n"
                    f"Stdout: {e.stdout}\nStderr: {e.stderr}"
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent solution timed out on input {str_val}")

            assert oracle_out == agent_out, (
                f"Mismatch on input {str_val}:\n"
                f"Oracle: '{oracle_out}'\nAgent : '{agent_out}'"
            )
    finally:
        os.rename(hidden_oracle, ORACLE_PATH)
        os.rmdir(hidden_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
