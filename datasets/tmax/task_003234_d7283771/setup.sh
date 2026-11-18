#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate audio memo
    espeak -w /app/audit_memo.wav "For this quarter's compliance audit, we must establish direct accountability chains. Ensure you map the shortest path from the root entity to the target entity. However, strictly ignore any entities with a risk score greater than 74. I repeat, a risk score greater than 74 invalidates the entity for our routing."

    # Generate corporate_entities.json
    cat << 'EOF' > /app/generate_graph.py
import json
import random

random.seed(42)
nodes = ["CORP-ROOT"] + [f"CORP-{i}" for i in range(1, 1000)]
data = []
for n in nodes:
    conns = random.sample(nodes, random.randint(1, 10))
    if n in conns:
        conns.remove(n)
    data.append({
        "entity_id": n,
        "risk_score": random.randint(1, 100),
        "connections": conns
    })

with open("/app/corporate_entities.json", "w") as f:
    json.dump(data, f)
EOF
    python3 /app/generate_graph.py
    rm /app/generate_graph.py

    # Create oracle
    cat << 'EOF' > /app/oracle_audit_path_finder
#!/usr/bin/env python3
import sys
import json
from collections import deque

def main():
    if len(sys.argv) < 2:
        return
    target = sys.argv[1]
    with open("/app/corporate_entities.json", "r") as f:
        data = json.load(f)

    graph = {}
    risk = {}
    for item in data:
        graph[item["entity_id"]] = item["connections"]
        risk[item["entity_id"]] = item["risk_score"]

    if "CORP-ROOT" not in graph or risk.get("CORP-ROOT", 100) > 74:
        print("NO_COMPLIANT_PATH")
        return

    q = deque([("CORP-ROOT", ["CORP-ROOT"])])
    visited = set(["CORP-ROOT"])

    while q:
        curr, path = q.popleft()
        if curr == target:
            print(",".join(path))
            return

        for nxt in graph.get(curr, []):
            if nxt not in visited:
                if risk.get(nxt, 100) <= 74:
                    visited.add(nxt)
                    q.append((nxt, path + [nxt]))

    print("NO_COMPLIANT_PATH")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_audit_path_finder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
