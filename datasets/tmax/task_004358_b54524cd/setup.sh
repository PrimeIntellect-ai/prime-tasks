#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest networkx==2.8.8

    # Vendor networkx 2.8.8
    mkdir -p /app/networkx
    pip3 download networkx==2.8.8 --no-deps --no-binary :all: -d /tmp
    tar -xzf /tmp/networkx-2.8.8.tar.gz -C /tmp
    cp -r /tmp/networkx-2.8.8/* /app/networkx/

    # Introduce the perturbation
    sed -i '20i imprt sys' /app/networkx/networkx/classes/digraph.py

    # Create the oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/reference_backup_analyzer.py
import sys
import json
import csv
import networkx as nx

def main():
    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, 'r') as f:
        data = json.load(f)

    G = nx.DiGraph()
    durations = {}

    for job in data:
        jid = job['job_id']
        durations[jid] = job['duration_minutes']
        G.add_node(jid)
        for dep in job.get('depends_on', []):
            G.add_edge(dep, jid)

    results = []
    for node in G.nodes():
        descendants = nx.descendants(G, node) | {node}
        ancestors = nx.ancestors(G, node) | {node}

        sum_duration = sum(durations[d] for d in descendants)
        count_ancestors = len(ancestors)

        score = sum_duration * count_ancestors
        results.append((node, score))

    results.sort(key=lambda x: x[0])

    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['job_id', 'criticality_score'])
        for r in results:
            writer.writerow([r[0], r[1]])

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
