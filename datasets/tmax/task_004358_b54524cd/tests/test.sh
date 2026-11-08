#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import json
import csv
import string
import random
import subprocess
import tempfile
import pytest

def test_networkx_fixed():
    """Verify that the syntax error in digraph.py has been fixed."""
    path = "/app/networkx/networkx/classes/digraph.py"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "imprt sys" not in content, "The syntax error 'imprt sys' is still present in digraph.py."
    assert "import sys" in content, "The expected 'import sys' is not found in digraph.py."

def generate_random_dag(num_nodes):
    """Generate a random DAG of backup jobs."""
    jobs = []
    created_job_ids = []

    for _ in range(num_nodes):
        length = random.randint(3, 8)
        job_id = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        while job_id in created_job_ids:
            job_id = ''.join(random.choices(string.ascii_letters + string.digits, k=length))

        duration = random.randint(1, 120)
        num_deps = random.randint(0, min(3, len(created_job_ids)))
        if num_deps > 0:
            depends_on = random.sample(created_job_ids, num_deps)
        else:
            depends_on = []

        jobs.append({
            "job_id": job_id,
            "depends_on": depends_on,
            "duration_minutes": duration
        })
        created_job_ids.append(job_id)

    return jobs

def test_backup_analyzer_fuzz_equivalence():
    """Fuzz equivalence test for the backup analyzer script."""
    agent_script = "/home/user/backup_analyzer.py"
    oracle_script = "/tests/reference_backup_analyzer.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)
    env = os.environ.copy()
    env["PYTHONPATH"] = "/app/networkx" + (":" + env["PYTHONPATH"] if "PYTHONPATH" in env else "")

    for i in range(50):
        num_nodes = random.randint(10, 100)
        dag = generate_random_dag(num_nodes)

        with tempfile.TemporaryDirectory() as tmpdir:
            input_json = os.path.join(tmpdir, "input.json")
            agent_out = os.path.join(tmpdir, "agent_out.csv")
            oracle_out = os.path.join(tmpdir, "oracle_out.csv")

            with open(input_json, "w") as f:
                json.dump(dag, f)

            agent_proc = subprocess.run(
                [sys.executable, agent_script, input_json, agent_out],
                env=env,
                capture_output=True,
                text=True
            )
            assert agent_proc.returncode == 0, f"Agent script failed on fuzz iteration {i}. Stderr: {agent_proc.stderr}"
            assert os.path.isfile(agent_out), f"Agent script did not produce output file {agent_out}"

            oracle_proc = subprocess.run(
                [sys.executable, oracle_script, input_json, oracle_out],
                env=env,
                capture_output=True,
                text=True
            )
            assert oracle_proc.returncode == 0, f"Oracle script failed on fuzz iteration {i}. Stderr: {oracle_proc.stderr}"
            assert os.path.isfile(oracle_out), f"Oracle script did not produce output file {oracle_out}"

            with open(agent_out, "r") as f:
                agent_csv = f.read()
            with open(oracle_out, "r") as f:
                oracle_csv = f.read()

            assert agent_csv == oracle_csv, (
                f"Output mismatch on fuzz iteration {i}.\n"
                f"Input JSON:\n{json.dumps(dag, indent=2)}\n\n"
                f"Oracle Output:\n{oracle_csv}\n\n"
                f"Agent Output:\n{agent_csv}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
