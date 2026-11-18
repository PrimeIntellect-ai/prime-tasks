#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /app/sql-graph-emulator/sge
cat << 'EOF' > /app/sql-graph-emulator/setup.py
from setuptools import setup, find_packages
setup(name='sql-graph-emulator', version='1.2.0', packages=find_packages())
EOF

cat << 'EOF' > /app/sql-graph-emulator/sge/__init__.py
from .executor import GraphDatabase
EOF

cat << 'EOF' > /app/sql-graph-emulator/sge/executor.py
class GraphDatabase:
    def __init__(self, data):
        self.nodes = {n['id']: n for n in data.get('nodes', [])}
        self.edges = data.get('edges', [])

    def _join_edges(self, parent_edges, child_edges):
        # PERTURBATION: Implicit cross join
        return [(e1, e2) for e1 in parent_edges for e2 in child_edges]

    def get_children(self, node_id):
        return [e['child'] for e in self.edges if e['parent'] == node_id]

    def recursive_aggregate(self):
        # A simple recursive aggregator that users of this library would call.
        # Note: the test evaluates if they use the library correctly and fix the core engine logic
        # (even if they bypass _join_edges and write their own graph traversal, they must fix the package
        # as requested, though fuzz equivalence checks the final output).
        def dfs(n_id):
            total = self.nodes[n_id].get('value', 0)
            for child_id in self.get_children(n_id):
                total += dfs(child_id)
            return total
        return {n: dfs(n) for n in self.nodes}
EOF

# Setup the oracle
mkdir -p /opt/oracle
cat << 'EOF' > /opt/oracle/solve_oracle.py
#!/usr/bin/env python3
import sys, json, csv
def solve(json_path):
    with open(json_path) as f:
        data = json.load(f)
    nodes = {n['id']: n['value'] for n in data['nodes']}
    edges = {}
    for e in data['edges']:
        edges.setdefault(e['parent'], []).append(e['child'])

    memo = {}
    def dfs(node_id):
        if node_id in memo: return memo[node_id]
        total = nodes.get(node_id, 0)
        for child in edges.get(node_id, []):
            total += dfs(child)
        memo[node_id] = total
        return total

    results = []
    for n in sorted(nodes.keys()):
        results.append([n, dfs(n)])

    writer = csv.writer(sys.stdout)
    writer.writerow(["id", "total_value"])
    writer.writerows(results)

if __name__ == "__main__":
    solve(sys.argv[1])
EOF
chmod +x /opt/oracle/solve_oracle.py

useradd -m -s /bin/bash user || true
chown -R user:user /app/sql-graph-emulator
chmod -R 777 /home/user
