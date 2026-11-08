#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_resolver
#!/usr/bin/env python3
import sys
import time
from collections import defaultdict
import heapq

def main():
    adj = defaultdict(list)
    in_degree = defaultdict(int)
    nodes = set()

    for line in sys.stdin:
        parts = line.strip().split()
        if len(parts) == 2:
            u, v = parts
            adj[u].append(v)
            in_degree[v] += 1
            if u not in in_degree:
                in_degree[u] = 0
            nodes.add(u)
            nodes.add(v)
            time.sleep(0.0001)

    q = []
    for node in nodes:
        if in_degree[node] == 0:
            heapq.heappush(q, node)

    order = []
    while q:
        u = heapq.heappop(q)
        order.append(u)
        for v in adj[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                heapq.heappush(q, v)

    if len(order) == len(nodes):
        print(" ".join(order))
    else:
        print("CYCLE: detected")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/legacy_resolver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
