#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import tempfile
import pytest


def test_optimized_engine_exists():
    agent_script = "/home/user/optimized_cost_engine.py"
    assert os.path.exists(agent_script), f"Agent's script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"{agent_script} is not a file."


def test_fuzz_equivalence():
    oracle_bin = "/app/legacy_join_cost_engine"
    agent_script = "/home/user/optimized_cost_engine.py"

    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} missing."
    assert os.path.exists(agent_script), f"Agent script {agent_script} missing."

    random.seed(42)
    pairs = [
        (random.randint(1, 100), random.randint(1, 100))
        for _ in range(1000)
    ]

    expected = []
    for src_id, dst_id in pairs:
        oracle_cmd = [oracle_bin, str(src_id), str(dst_id)]
        try:
            oracle_res = subprocess.run(
                oracle_cmd, capture_output=True, text=True, check=True
            )
            expected.append(oracle_res.stdout.strip())
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {src_id} {dst_id}: {e.stderr}")

    # Keep the oracle unavailable for every submitted-script invocation so the
    # replacement cannot delegate its work to the legacy executable.
    with open(oracle_bin, "rb") as f:
        oracle_data = f.read()
    oracle_mode = stat.S_IMODE(os.stat(oracle_bin).st_mode)
    os.unlink(oracle_bin)

    try:
        for (src_id, dst_id), oracle_out in zip(pairs, expected):
            agent_cmd = ["python3", agent_script, str(src_id), str(dst_id)]
            try:
                agent_res = subprocess.run(
                    agent_cmd, capture_output=True, text=True, check=True
                )
                agent_out = agent_res.stdout.strip()
            except subprocess.CalledProcessError as e:
                pytest.fail(
                    f"Agent script failed on input {src_id} {dst_id}: {e.stderr}"
                )

            assert agent_out == oracle_out, (
                f"Mismatch on inputs src_table_id={src_id}, dst_table_id={dst_id}.\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output: {agent_out}"
            )
    finally:
        fd, restore_path = tempfile.mkstemp(prefix=".legacy_restore_", dir="/app")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(oracle_data)
            os.chmod(restore_path, oracle_mode)
            os.replace(restore_path, oracle_bin)
        finally:
            if os.path.exists(restore_path):
                os.unlink(restore_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
