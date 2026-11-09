#!/bin/bash
set -e
mkdir -p /logs/verifier

FIXTURE_DIR=/tmp/verifier_graph_fixture
rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR/data"
chmod 700 "$FIXTURE_DIR" "$FIXTURE_DIR/data"

cat << 'EOF' > "$FIXTURE_DIR/naive_pipeline.json"
[
  {
    "$lookup": {
      "from": "edges",
      "localField": "node_id",
      "foreignField": "source_id",
      "as": "outgoing_edges"
    }
  },
  {
    "$unwind": "$outgoing_edges"
  },
  {
    "$lookup": {
      "from": "nodes",
      "localField": "outgoing_edges.target_id",
      "foreignField": "node_id",
      "as": "target_node"
    }
  },
  {
    "$unwind": "$target_node"
  },
  {
    "$match": {
      "type": "Server",
      "region": "us-east",
      "outgoing_edges.relationship_type": "depends_on",
      "target_node.type": "Database",
      "target_node.status": "offline"
    }
  },
  {
    "$project": {
      "server_id": "$node_id",
      "database_id": "$target_node.node_id"
    }
  }
]
EOF

python3 - << 'PY'
import csv
import random

root = "/tmp/verifier_graph_fixture/data"
random.seed(42)
nodes = []
for i in range(1, 401):
    if i <= 10:
        nodes.append({"node_id": f"n{i}", "type": "Server", "status": "online", "region": "us-east"})
    elif i <= 20:
        nodes.append({"node_id": f"n{i}", "type": "Database", "status": "offline", "region": "us-west"})
    else:
        nodes.append({"node_id": f"n{i}", "type": "Client", "status": "online", "region": "eu-central"})

edges = []
for i in range(1, 11):
    edges.append({"source_id": f"n{i}", "target_id": f"n{i+10}", "relationship_type": "depends_on", "weight": 1})
for _ in range(400):
    edges.append({"source_id": f"n{random.randint(21, 400)}", "target_id": f"n{random.randint(21, 400)}", "relationship_type": "connected_to", "weight": random.randint(1, 5)})

with open(root + "/nodes.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["node_id", "type", "status", "region"])
    writer.writeheader()
    writer.writerows(nodes)
with open(root + "/edges.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["source_id", "target_id", "relationship_type", "weight"])
    writer.writeheader()
    writer.writerows(edges)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import time
import pytest

FIXTURE_DIR = "/tmp/verifier_graph_fixture"
CANONICAL_NAIVE = FIXTURE_DIR + "/naive_pipeline.json"
NODES = FIXTURE_DIR + "/data/nodes.csv"
EDGES = FIXTURE_DIR + "/data/edges.csv"


def run_engine(pipeline_path, out_path):
    start = time.perf_counter()
    cmd = [
        "/app/graph_engine",
        "--nodes", NODES,
        "--edges", EDGES,
        "--pipeline", pipeline_path,
        "--out", out_path,
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    duration = time.perf_counter() - start
    with open(out_path, "r") as f:
        data = json.load(f)
    return duration, data


def test_optimized_pipeline_exists():
    assert os.path.isfile("/home/user/optimized_pipeline.json"), "/home/user/optimized_pipeline.json is missing"


def test_pipeline_accuracy_and_speedup():
    naive_pipeline = "/home/user/naive_pipeline.json"
    opt_pipeline = "/home/user/optimized_pipeline.json"

    assert os.path.isfile(naive_pipeline), f"{naive_pipeline} is missing"
    assert os.path.isfile(opt_pipeline), f"{opt_pipeline} is missing"

    with open(CANONICAL_NAIVE, "r") as f:
        canonical_naive = json.load(f)
    with open(naive_pipeline, "r") as f:
        installed_naive = json.load(f)
    assert installed_naive == canonical_naive, "The supplied naive pipeline was modified."

    with open(opt_pipeline, "r") as f:
        optimized = json.load(f)
    assert isinstance(optimized, list), "The optimized pipeline must be a JSON array."

    naive_out_path = FIXTURE_DIR + "/naive_out.json"
    opt_out_path = FIXTURE_DIR + "/opt_out.json"

    try:
        time_naive, out_naive = run_engine(CANONICAL_NAIVE, naive_out_path)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run naive pipeline: {e}")

    try:
        time_opt, out_opt = run_engine(opt_pipeline, opt_out_path)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run optimized pipeline: {e}")

    out_naive_sorted = sorted(out_naive, key=lambda x: str(x))
    out_opt_sorted = sorted(out_opt, key=lambda x: str(x))
    assert out_naive_sorted == out_opt_sorted, "The output of the optimized pipeline does not match the naive pipeline."

    speedup = time_naive / time_opt if time_opt > 0 else float("inf")
    assert speedup >= 5.0, f"Speedup is {speedup:.2f}x, which is less than the required 5.0x."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
