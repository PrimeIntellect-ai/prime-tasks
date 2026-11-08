#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy setuptools

    mkdir -p /app/mcmc_graph_solver/mcmc_graph_solver
    mkdir -p /app/mcmc_graph_solver/tests
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Vendored package setup.py
    cat << 'EOF' > /app/mcmc_graph_solver/setup.py
from setuptools import setup, find_packages
setup(
    name="mcmc_graph_solver",
    version="1.0",
    packages=find_packages(),
)
EOF

    # Vendored package __init__.py
    touch /app/mcmc_graph_solver/mcmc_graph_solver/__init__.py

    # Vendored package core.py
    cat << 'EOF' > /app/mcmc_graph_solver/mcmc_graph_solver/core.py
import numpy as np

class GraphSolver:
    def __init__(self, edges):
        raw_nodes = []
        for u, v in edges:
            raw_nodes.extend([u, v])
        # Extract unique nodes (bug: unordered set causes non-deterministic matrix construction)
        self.nodes = list(set(raw_nodes))
        self.edges = edges

    def solve(self):
        n = len(self.nodes)
        node_idx = {node: i for i, node in enumerate(self.nodes)}
        P = np.zeros((n, n))
        for u, v in self.edges:
            P[node_idx[u], node_idx[v]] = 1.0

        for i in range(n):
            row_sum = np.sum(P[i])
            if row_sum > 0:
                P[i] /= row_sum
            else:
                P[i, i] = 1.0

        evals, evecs = np.linalg.eig(P.T)
        idx = np.argmin(np.abs(evals - 1.0))
        pi = np.real(evecs[:, idx])
        pi /= np.sum(pi)

        return {self.nodes[i]: pi[i] for i in range(n)}
EOF

    # Vendored package test
    cat << 'EOF' > /app/mcmc_graph_solver/tests/test_reproducibility.py
import pytest
from mcmc_graph_solver.core import GraphSolver

def test_reproducibility():
    edges = [(str(i), str((i+1)%20)) for i in range(20)]
    edges += [(str(i), str((i+2)%20)) for i in range(20)]

    solver = GraphSolver(edges)

    # The nodes must be sorted to ensure deterministic transition matrix construction
    # and avoid floating-point reduction order variations.
    assert solver.nodes == sorted(solver.nodes), "Nodes list is not deterministic!"
EOF

    # Clean corpus (strongly connected graphs)
    cat << 'EOF' > /app/corpora/clean/graph1.json
{"1": ["2"], "2": ["3"], "3": ["1"]}
EOF
    cat << 'EOF' > /app/corpora/clean/graph2.json
{"A": ["B", "C"], "B": ["C", "A"], "C": ["A", "B"]}
EOF

    # Evil corpus (not strongly connected graphs)
    cat << 'EOF' > /app/corpora/evil/graph1.json
{"1": ["2"], "2": ["3"], "3": []}
EOF
    cat << 'EOF' > /app/corpora/evil/graph2.json
{"A": ["B"], "B": ["C"], "C": ["C"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
