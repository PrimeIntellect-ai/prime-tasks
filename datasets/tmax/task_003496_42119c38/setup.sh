#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Generate network_events.jsonl
    cat << 'EOF' > generate_data.py
import json
import random

random.seed(42)
users = [f"user_{i}" for i in range(1, 101)]

edges = []
# Create a star topology for user_1
for u in users[1:50]:
    edges.append({"source": u, "target": "user_1", "timestamp": 1610000000, "type": "message"})

# Create a dense cluster for user_2 to user_10
for i in range(1, 10):
    for j in range(1, 10):
        if i != j:
            edges.append({"source": users[i], "target": users[j], "timestamp": 1610000000, "type": "message"})

# Add random edges
for _ in range(500):
    src = random.choice(users)
    tgt = random.choice(users)
    if src != tgt:
        edges.append({"source": src, "target": tgt, "timestamp": 1610000000, "type": "message"})

with open("network_events.jsonl", "w") as f:
    for e in edges:
        f.write(json.dumps(e) + "\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    # Create the slow script compute_metrics.py
    cat << 'EOF' > compute_metrics.py
import json

def get_users():
    users = set()
    with open("network_events.jsonl", "r") as f:
        for line in f:
            data = json.loads(line)
            users.add(data["source"])
            users.add(data["target"])
    return sorted(list(users))

def get_incoming_edges(user):
    incoming = []
    with open("network_events.jsonl", "r") as f:
        for line in f:
            data = json.loads(line)
            if data["target"] == user:
                incoming.append(data["source"])
    return incoming

def get_outgoing_edges(user):
    outgoing = []
    with open("network_events.jsonl", "r") as f:
        for line in f:
            data = json.loads(line)
            if data["source"] == user:
                outgoing.append(data["target"])
    return outgoing

users = get_users()

# This is incredibly slow O(N * E)
in_degrees = {}
for u in users:
    in_degrees[u] = len(get_incoming_edges(u))

ranks = {u: 1.0 for u in users}
for iteration in range(2):
    new_ranks = {u: 0.0 for u in users}
    for u in users:
        out_edges = get_outgoing_edges(u)
        if out_edges:
            share = ranks[u] / len(out_edges)
            for target in out_edges:
                new_ranks[target] += share
    ranks = new_ranks

print("Done. (Too slow to actually output)")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
