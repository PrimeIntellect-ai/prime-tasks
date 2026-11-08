#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest

    # Download and vendor networkx 2.8.8
    mkdir -p /app
    cd /app
    curl -sSL https://github.com/networkx/networkx/archive/refs/tags/networkx-2.8.8.tar.gz | tar -xz
    mv networkx-networkx-2.8.8 networkx

    # Apply perturbation
    sed -i 's/self._succ\[u_of_edge\]\[v_of_edge\] = datadict/self._succ[u_of_edge][u_of_edge] = datadict/g' /app/networkx/networkx/classes/digraph.py

    # Create oracle script
    mkdir -p /test
    cat << 'EOF' > /test/oracle.py
import sys
import csv
from collections import deque

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    csv_file = sys.argv[1]
    target = sys.argv[2]

    adj = {}
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = row['tx']
            v = row['waiting_for']
            if u not in adj: adj[u] = []
            if v not in adj: adj[v] = []
            adj[u].append(v)

    if target not in adj:
        print("NO_DEADLOCK")
        return

    q = deque([(target, [target])])
    visited = {target: 0}

    shortest_cycles = []
    min_len = float('inf')

    while q:
        curr, path = q.popleft()

        if len(path) > min_len:
            break

        for nxt in adj.get(curr, []):
            if nxt == target:
                cycle_len = len(path)
                if cycle_len < min_len:
                    min_len = cycle_len
                    shortest_cycles = [path + [target]]
                elif cycle_len == min_len:
                    shortest_cycles.append(path + [target])
            elif nxt not in visited or visited[nxt] == len(path):
                visited[nxt] = len(path)
                q.append((nxt, path + [nxt]))

    if not shortest_cycles:
        print("NO_DEADLOCK")
    else:
        shortest_cycles.sort()
        print(",".join(shortest_cycles[0]))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /test
