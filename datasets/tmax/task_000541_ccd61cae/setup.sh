#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipelines

    cat << 'EOF' > /home/user/pipelines/valid.pipeline
job build:
  requires: []
job lint:
  requires: []
job test:
  requires: [build, lint]
job deploy:
  requires: [test]
EOF

    cat << 'EOF' > /home/user/pipelines/circular.pipeline
job setup:
  requires: []
job compile:
  requires: [setup, link]
job test:
  requires: [compile]
job link:
  requires: [test]
EOF

    cat << 'EOF' > /home/user/legacy_parser.py
import sys
import re

def parse_and_sort(filepath):
    # Intentional naive, memory-leaking, infinite-looping code
    nodes = {}
    with open(filepath, 'r') as f:
        current_job = None
        for line in f:
            line = line.strip()
            if line.startswith('job '):
                current_job = line[4:-1]
                if current_job not in nodes:
                    nodes[current_job] = []
            elif line.startswith('requires:'):
                reqs = re.search(r'\[(.*)\]', line).group(1)
                if reqs:
                    for r in reqs.split(','):
                        nodes[current_job].append(r.strip())

    # Inefficient topological sort that hangs on cycles
    order = []
    while len(order) < len(nodes):
        for node, edges in nodes.items():
            if node not in order and all(e in order for e in edges):
                order.append(node)
                # Leak memory intentionally to simulate bad old script
                nodes[node] = nodes[node] * 10 

    print("RESULT: SUCCESS")
    print("ORDER: " + ", ".join(order))

if __name__ == "__main__":
    parse_and_sort(sys.argv[1])
EOF

    chmod +x /home/user/legacy_parser.py
    chmod -R 777 /home/user
