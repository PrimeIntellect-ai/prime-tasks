#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

# Start a clean Redis instance for the submitted pipeline.
pkill -x redis-server >/dev/null 2>&1 || true
redis-server --daemonize yes

# Recreate and start the deterministic transaction service used by the task.
cat << 'API_EOF' > /tmp/verifier_api.py
from fastapi import FastAPI
import random

app = FastAPI()
random.seed(42)
transactions = []
for i in range(5000):
    transactions.append({
        "tx_id": f"tx_{i}",
        "sender_id": f"U-{random.randint(1, 200):03d}",
        "receiver_id": f"U-{random.randint(1, 200):03d}",
        "amount": round(random.uniform(10, 1000), 2),
        "timestamp": "2023-01-01T00:00:00Z",
    })

@app.get("/transactions")
def get_transactions(page: int = 1):
    page_size = 100
    start = (page - 1) * page_size
    if start >= len(transactions):
        return []
    if page > 1:
        start = max(0, start - 20)
    end = page * page_size
    return transactions[start:end]
API_EOF

pkill -f 'uvicorn.*8080' >/dev/null 2>&1 || true
PYTHONPATH=/tmp python3 -m uvicorn verifier_api:app --host 127.0.0.1 --port 8080 >/tmp/verifier_api.log 2>&1 &
API_PID=$!
trap 'kill "$API_PID" >/dev/null 2>&1 || true' EXIT

python3 - <<'PY'
import requests
import time

for _ in range(100):
    try:
        if requests.get("http://127.0.0.1:8080/transactions?page=1", timeout=0.2).status_code == 200:
            break
    except requests.RequestException:
        pass
    time.sleep(0.1)
else:
    raise SystemExit("Transaction API failed to start")
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import subprocess

import networkx as nx
import pytest
import redis

SCRIPT = "/home/user/workspace/pipeline.py"
DONE = "/home/user/workspace/done"
FRAUDS = {"U-991", "U-042", "U-777"}


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."

    r = redis.Redis(host="localhost", port=6379, decode_responses=True)
    r.ping()
    r.delete("fraud_scores")

    account = pwd.getpwnam("user")

    def demote():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
            preexec_fn=demote,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("pipeline.py exceeded the 30 second time limit.")

    assert result.returncode == 0, "pipeline.py failed:\n" + result.stdout[-4000:]


def exact_top_100():
    random.seed(42)
    graph = nx.DiGraph()

    # Generate the unique transactions independently. The API's stale rows are
    # duplicate tx_ids and therefore must not be counted again.
    for _ in range(5000):
        sender = f"U-{random.randint(1, 200):03d}"
        receiver = f"U-{random.randint(1, 200):03d}"
        amount = round(random.uniform(10, 1000), 2)
        if graph.has_edge(sender, receiver):
            graph[sender][receiver]["weight"] += amount
        else:
            graph.add_edge(sender, receiver, weight=amount)

    personalization = {node: (1.0 if node in FRAUDS else 0.0) for node in graph}
    scores = nx.pagerank(
        graph,
        alpha=0.85,
        personalization=personalization,
        weight="weight",
        max_iter=1000,
        tol=1.0e-12,
    )
    ranked = sorted(
        (node for node in graph if node not in FRAUDS),
        key=lambda node: (-scores[node], node),
    )
    return ranked[:100]


def test_pipeline_script_exists():
    assert os.path.isfile(SCRIPT), "The script /home/user/workspace/pipeline.py does not exist."


def test_done_file_exists():
    assert os.path.isfile(DONE), "The file /home/user/workspace/done does not exist. Ensure you create it when finished."


def test_redis_fraud_scores_accuracy():
    try:
        r = redis.Redis(host="localhost", port=6379, decode_responses=True)
        r.ping()
    except redis.exceptions.ConnectionError:
        pytest.fail("Could not connect to Redis server on localhost:6379.")

    submitted = r.zrevrange("fraud_scores", 0, 99)
    assert len(submitted) > 0, "Redis sorted set 'fraud_scores' is empty or does not exist."
    assert len(submitted) == 100, "Redis sorted set 'fraud_scores' must contain a full top 100."

    golden = exact_top_100()
    assert len(golden) == 100, "Exact top-100 calculation did not produce 100 accounts."

    overlap_count = len(set(submitted).intersection(set(golden)))
    accuracy = overlap_count / 100.0
    assert accuracy >= 0.95, f"Accuracy {accuracy:.2f} is below the threshold of 0.95. Only {overlap_count} out of 100 matched the exact top 100."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
