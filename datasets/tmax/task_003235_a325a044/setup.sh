#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user
    mkdir -p /app/data-flow-tracer/tracer
    mkdir -p /test

    # Create /home/user/system_schema.json
    cat << 'EOF' > /home/user/system_schema.json
{
    "nodes": [],
    "edges": []
}
EOF

    # Create /app/data-flow-tracer/run_audit.py
    cat << 'EOF' > /app/data-flow-tracer/run_audit.py
import argparse
import json
from tracer.mapper import map_edges

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input')
    parser.add_argument('--output')
    args = parser.parse_args()

    results = map_edges()

    with open(args.output, 'w') as f:
        json.dump(results, f)

if __name__ == "__main__":
    main()
EOF

    # Create /app/data-flow-tracer/tracer/__init__.py
    touch /app/data-flow-tracer/tracer/__init__.py

    # Create /app/data-flow-tracer/tracer/mapper.py
    cat << 'EOF' > /app/data-flow-tracer/tracer/mapper.py
def map_edges():
    query = "MATCH (d:Document)-[r:REFERENCES]->(g:RelationalNode)"
    edges = []
    for i in range(10):
        if i == 5:
            continue
        edges.append(i)
    return edges
EOF

    # Create /test/verify_f1.py
    cat << 'EOF' > /test/verify_f1.py
import json
import sys

def main():
    with open('/home/user/audit_results.json', 'r') as f:
        results = json.load(f)
    with open('/test/golden_results.json', 'r') as f:
        golden = json.load(f)

    # Dummy F1 calculation
    f1_score = 1.0 if results == golden else 0.0
    if f1_score >= 0.95:
        print("Pass")
        sys.exit(0)
    else:
        print("Fail")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    # Create /test/golden_results.json
    cat << 'EOF' > /test/golden_results.json
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /test
