#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import random
import subprocess
import os

def test_process_graph_fuzz_equivalence():
    agent_script = "/home/user/process_graph.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)

    for i in range(50):
        num_users = random.randint(10, 50)
        users = []
        user_ids = [f"U{j}" for j in range(num_users)]
        for uid in user_ids:
            users.append({
                "user_id": uid,
                "status": random.choice(["VERIFIED", "PENDING", "BANNED"])
            })

        num_transfers = random.randint(20, 100)
        transfers = []
        for _ in range(num_transfers):
            transfers.append({
                "source": random.choice(user_ids),
                "target": random.choice(user_ids),
                "amount": round(random.uniform(10.0, 500.0), 2)
            })

        payload = json.dumps({"users": users, "transfers": transfers})

        # Run oracle uploaded only at verification time.
        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=payload,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"

        # Run agent.
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=payload,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_proc.stderr}"

        try:
            oracle_out = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            oracle_out = oracle_proc.stdout.strip()

        try:
            agent_out = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i}.\n"
            f"Input payload:\n{payload}\n\n"
            f"Oracle output:\n{oracle_out}\n\n"
            f"Agent output:\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
