#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import json
import random

def test_agent_tool_exists_and_executable():
    path = '/home/user/restore_tool'
    assert os.path.isfile(path), f"Agent tool {path} does not exist."
    assert os.access(path, os.X_OK), f"Agent tool {path} is not executable."

def test_fuzz_equivalence():
    agent_tool = '/home/user/restore_tool'
    oracle_tool = '/tests/oracle_restore_tool'

    assert os.path.isfile(oracle_tool), f"Oracle tool {oracle_tool} missing."
    assert os.access(oracle_tool, os.X_OK), f"Oracle tool {oracle_tool} not executable."

    random.seed(42)
    job_ids = random.sample(range(1, 51), 20)

    for job_id in job_ids:
        # Run oracle
        oracle_cmd = [oracle_tool, '--job-id', str(job_id)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on job-id {job_id}:\n{oracle_res.stderr}"

        # Run agent
        agent_cmd = [agent_tool, '--job-id', str(job_id)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent failed on job-id {job_id}:\n{agent_res.stderr}"

        try:
            oracle_json = json.loads(oracle_res.stdout)
        except json.JSONDecodeError:
            assert False, f"Oracle output is not valid JSON on job-id {job_id}."

        try:
            agent_json = json.loads(agent_res.stdout)
        except json.JSONDecodeError:
            assert False, f"Agent output is not valid JSON on job-id {job_id}. Output:\n{agent_res.stdout}"

        assert agent_json == oracle_json, (
            f"Output mismatch on job-id {job_id}.\n"
            f"Expected:\n{json.dumps(oracle_json, indent=2)}\n\n"
            f"Got:\n{json.dumps(agent_json, indent=2)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
