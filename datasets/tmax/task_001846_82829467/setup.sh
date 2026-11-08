#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install --default-timeout=100 pytest

    mkdir -p /app

    # Generate audio fixture
    espeak -w /app/research_log.wav "Transaction TX_A acquired lock on resource RES_1. Transaction TX_B acquired lock on resource RES_2. Transaction TX_C acquired lock on resource RES_3. Transaction TX_A is waiting for resource RES_2. Transaction TX_B is waiting for resource RES_3. Transaction TX_C is waiting for resource RES_1. Transaction TX_D acquired lock on resource RES_4. Transaction TX_D is waiting for resource RES_2. Transaction TX_E is waiting for resource RES_4."

    # Create oracle
    cat << 'EOF' > /app/oracle_query_graph
#!/usr/bin/env python3
import sys

graph = {
    'TX_A': ['RES_2'],
    'RES_2': ['TX_B'],
    'TX_B': ['RES_3'],
    'RES_3': ['TX_C'],
    'TX_C': ['RES_1'],
    'RES_1': ['TX_A'],
    'TX_D': ['RES_2'],
    'TX_E': ['RES_4'],
    'RES_4': ['TX_D']
}

def find_cycles(node_id):
    paths = []
    def dfs(current, path):
        if len(path) > 6:
            return
        for neighbor in graph.get(current, []):
            if neighbor in path:
                paths.append(" -> ".join(path + [neighbor]))
            else:
                dfs(neighbor, path + [neighbor])
    dfs(node_id, [node_id])
    return sorted(paths)

if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(1)
    node_id = sys.argv[1]
    limit = int(sys.argv[2])
    offset = int(sys.argv[3])
    cycles = find_cycles(node_id)
    for p in cycles[offset:offset+limit]:
        print(p)
EOF
    chmod +x /app/oracle_query_graph

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
