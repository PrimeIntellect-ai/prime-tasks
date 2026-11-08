#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fuzz_graph(file_path, num_nodes):
    with open(file_path, "w") as f:
        f.write("@prefix ns: <http://example.org/backup#> .\n")
        f.write("@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n")

        for i in range(num_nodes):
            size = random.randint(10, 1000)
            time = random.randint(100000, 999999) + i * 1000
            f.write(f"ns:node_{i} ns:backupSize {size} ;\n")
            f.write(f"    ns:creationTime {time} .\n")

            if i > 0:
                parent = random.randint(0, i - 1)
                f.write(f"ns:node_{i} ns:dependsOn ns:node_{parent} .\n")
            f.write("\n")

def test_fuzz_equivalence():
    agent_script = "/home/user/backup_analyzer.py"
    oracle_script = "/tests/backup_analyzer_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    os.makedirs("/tmp/fuzz_graphs", exist_ok=True)
    random.seed(42)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/app/rdflib-source"

    for i in range(50):
        num_nodes = random.randint(5, 50)
        file_path = f"/tmp/fuzz_graphs/graph_{i}.ttl"
        generate_fuzz_graph(file_path, num_nodes)

        target = f"http://example.org/backup#node_{random.randint(0, num_nodes - 1)}"

        agent_cmd = ["/usr/bin/python3", agent_script, file_path, target]
        oracle_cmd = ["/usr/bin/python3", oracle_script, file_path, target]

        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, env=env)
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, env=env)

        assert agent_res.returncode == 0, f"Agent script failed on {file_path} {target}:\n{agent_res.stderr}"
        assert oracle_res.returncode == 0, f"Oracle script failed on {file_path} {target}:\n{oracle_res.stderr}"

        assert agent_res.stdout.strip() == oracle_res.stdout.strip(), (
            f"Mismatch on {file_path} {target}:\n"
            f"Expected:\n{oracle_res.stdout.strip()}\n"
            f"Got:\n{agent_res.stdout.strip()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
