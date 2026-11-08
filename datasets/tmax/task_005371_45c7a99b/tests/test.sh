#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import random
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_query_tool.py"
AGENT_PATH = "/home/user/query_tool.py"
CSV_PATH = "/home/user/org_chart.csv"

def get_dept_ids(csv_path):
    dept_ids = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            dept_ids.append(row['dept_id'])
    return dept_ids

def run_script(script_path, start_sec, end_sec, dept_id):
    cmd = ["python3", script_path, str(start_sec), str(end_sec), dept_id]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None, f"Script {script_path} failed with return code {result.returncode}.\nStderr: {result.stderr}"

    try:
        output_json = json.loads(result.stdout.strip())
        return output_json, None
    except json.JSONDecodeError:
        return None, f"Script {script_path} did not output valid JSON.\nStdout: {result.stdout}"

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle script missing at {ORACLE_PATH}"
    assert os.path.isfile(CSV_PATH), f"CSV file missing at {CSV_PATH}"

    dept_ids = get_dept_ids(CSV_PATH)
    assert len(dept_ids) > 0, "No dept_ids found in CSV."

    random.seed(42)
    N = 100

    for i in range(N):
        start_sec = random.randint(0, 59)
        end_sec = random.randint(start_sec, 59)
        dept_id = random.choice(dept_ids)

        oracle_out, oracle_err = run_script(ORACLE_PATH, start_sec, end_sec, dept_id)
        assert oracle_err is None, f"Oracle failed on run {i}: {oracle_err}"

        agent_out, agent_err = run_script(AGENT_PATH, start_sec, end_sec, dept_id)
        assert agent_err is None, f"Agent failed on run {i} with input ({start_sec}, {end_sec}, {dept_id}): {agent_err}"

        assert oracle_out == agent_out, (
            f"Mismatch on run {i} with input (start_sec={start_sec}, end_sec={end_sec}, dept_id={dept_id}).\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
