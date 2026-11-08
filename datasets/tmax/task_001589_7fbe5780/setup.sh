#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gawk \
        sqlite3 \
        strace \
        binutils \
        coreutils

    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /app/legacy_auditor.py
import sys, csv, heapq
from collections import defaultdict

def solve():
    if len(sys.argv) != 2: return
    target = sys.argv[1]
    edges = defaultdict(dict)

    for row in csv.reader(sys.stdin):
        if len(row) != 4: continue
        u, v, ts, amt = row
        try: 
            ts, amt = int(ts), int(amt)
        except: 
            continue
        if amt <= 0: continue

        if v not in edges[u] or ts < edges[u][v][0]:
            edges[u][v] = (ts, amt)

    pq = []
    heapq.heappush(pq, (0, ["ADMIN"]))
    visited = set()
    best_path = None

    while pq:
        dist, path = heapq.heappop(pq)
        u = path[-1]

        if u == target:
            best_path = path
            break

        if u in visited: continue
        visited.add(u)

        for v in edges[u]:
            if v not in visited:
                heapq.heappush(pq, (dist + 1, path + [v]))

    if not best_path:
        print(f"No path found to {target}")
    else:
        max_amt = 0
        for i in range(len(best_path)-1):
            max_amt = max(max_amt, edges[best_path[i]][best_path[i+1]][1])
        print(f"Audit Path: {' -> '.join(best_path)} | Risk Score: {max_amt}")

if __name__ == "__main__": 
    solve()
EOF

    cd /app
    pyinstaller --onefile legacy_auditor.py
    mv dist/legacy_auditor /app/legacy_auditor
    strip /app/legacy_auditor
    rm -rf build dist legacy_auditor.spec legacy_auditor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
