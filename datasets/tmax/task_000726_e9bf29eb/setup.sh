#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest flask requests

    mkdir -p /app/vendored
    cd /app/vendored
    wget https://files.pythonhosted.org/packages/source/n/networkx/networkx-2.8.8.tar.gz
    tar -xzf networkx-2.8.8.tar.gz
    rm networkx-2.8.8.tar.gz

    sed -i '/def lexicographical_topological_sort(G, key=None):/a \    raise_syntax_error_here()' /app/vendored/networkx-2.8.8/networkx/algorithms/dag.py

    cat << 'EOF' > /app/oracle_planner.py
import sys
import json
import heapq

def solve(input_json_str):
    data = json.loads(input_json_str)
    tasks = data['tasks']
    dependencies = data['dependencies']
    max_cost = data['max_cost_per_batch']

    adj = {t: [] for t in tasks}
    in_degree = {t: 0 for t in tasks}

    for u, v in dependencies:
        adj[u].append(v)
        in_degree[v] += 1

    pq = []
    for t in tasks:
        if in_degree[t] == 0:
            heapq.heappush(pq, t)

    sorted_tasks = []
    while pq:
        u = heapq.heappop(pq)
        sorted_tasks.append(u)
        for v in adj[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                heapq.heappush(pq, v)

    batches = []
    current_batch = []
    current_cost = 0

    for t in sorted_tasks:
        cost = tasks[t]['cost']
        if current_cost + cost > max_cost and current_batch:
            batches.append(current_batch)
            current_batch = [t]
            current_cost = cost
        else:
            current_batch.append(t)
            current_cost += cost

    if current_batch:
        batches.append(current_batch)

    print(json.dumps(batches))

if __name__ == '__main__':
    solve(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
