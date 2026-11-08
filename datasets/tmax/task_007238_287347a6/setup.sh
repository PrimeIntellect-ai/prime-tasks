#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import heapq

def setup_environment():
    random.seed(42)
    artifacts_dir = "/home/user/artifacts"
    expected_dir = "/tmp/expected"
    os.makedirs(artifacts_dir, exist_ok=True)
    os.makedirs(expected_dir, exist_ok=True)

    # Create 40 nodes
    num_nodes = 40
    nodes = [f"artifact_{i:02d}.dat" for i in range(num_nodes)]

    # Generate DAG
    dependencies = {node: [] for node in nodes}
    for i in range(1, num_nodes):
        # Each node depends on 0 to 3 prior nodes to ensure a DAG
        num_deps = random.randint(0, 3)
        deps = random.sample(nodes[:i], num_deps)
        dependencies[nodes[i]] = deps

    # Generate data
    data_arrays = {}
    for node in nodes:
        data_arrays[node] = [random.randint(0, 10000) for _ in range(500)]

    # Write files
    for node in nodes:
        with open(os.path.join(artifacts_dir, node), "w") as f:
            deps_str = " ".join(dependencies[node])
            f.write(f"DEPENDS: {deps_str}\n")
            data_str = " ".join(map(str, data_arrays[node]))
            f.write(f"{data_str}\n")

    # Compute golden topological sort with alphabetical tie-breaking
    # Kahn's algorithm with priority queue
    adj = {node: [] for node in nodes}
    in_degree = {node: 0 for node in nodes}
    for u, deps in dependencies.items():
        for v in deps:
            adj[v].append(u)
            in_degree[u] += 1

    queue = [n for n in nodes if in_degree[n] == 0]
    heapq.heapify(queue)

    topo_order = []
    while queue:
        curr = heapq.heappop(queue)
        topo_order.append(curr)
        for neighbor in adj[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(queue, neighbor)

    # Compute golden state
    state = [0] * 500
    for node in topo_order:
        for i in range(500):
            state[i] = (state[i] + data_arrays[node][i]) % 10007

    # Write expected outputs
    with open(os.path.join(expected_dir, "build_order.log"), "w") as f:
        for node in topo_order:
            f.write(f"{node}\n")

    with open(os.path.join(expected_dir, "final_artifact.dat"), "w") as f:
        f.write(" ".join(map(str, state)) + "\n")

if __name__ == "__main__":
    setup_environment()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
    chmod -R 777 /tmp/expected
