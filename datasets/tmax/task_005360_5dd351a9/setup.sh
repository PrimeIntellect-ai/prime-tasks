#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/alert.wav "Node identifier is S R V dash Edge dash four two"

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/infrastructure_graph.json
{
  "SRV-EDGE-42": {"NODE-A": 50, "NODE-B": 100},
  "NODE-A": {"NODE-C": 40, "DB-CORE-99": 200},
  "NODE-B": {"NODE-C": 10, "DB-CORE-99": 60},
  "NODE-C": {"DB-CORE-99": 35},
  "DB-CORE-99": {}
}
EOF

    cat << 'EOF' > /home/user/slow_traversal.py
import sys
import json

def find_shortest_path(graph, start, end, path=None, latency=0):
    if path is None:
        path = []
    path = path + [start]
    if start == end:
        return path, latency
    if start not in graph:
        return None, float('inf')

    shortest = None
    min_latency = float('inf')

    for node, weight in graph[start].items():
        if node not in path:
            new_path, new_latency = find_shortest_path(graph, node, end, path, latency + weight)
            if new_path:
                if new_latency < min_latency:
                    shortest = new_path
                    min_latency = new_latency

    return shortest, min_latency

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 slow_traversal.py <start_node>")
        sys.exit(1)

    start_node = sys.argv[1]
    with open("/home/user/infrastructure_graph.json", "r") as f:
        graph = json.load(f)

    path, latency = find_shortest_path(graph, start_node, "DB-CORE-99")

    with open("/home/user/path_result.json", "w") as f:
        json.dump({"start_node": start_node, "path": path, "total_latency": latency}, f)
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
