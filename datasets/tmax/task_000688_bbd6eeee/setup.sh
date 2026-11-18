#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy scikit-learn

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/graph.json
{
  "0": ["1", "2", "3", "10"],
  "1": ["0", "2", "11"],
  "2": ["0", "1", "12"],
  "3": ["0", "4", "5"],
  "4": ["3", "5", "6"],
  "5": ["3", "4", "7"],
  "6": ["4", "8"],
  "7": ["5", "8"],
  "8": ["6", "7", "9"],
  "9": ["8", "10"],
  "10": ["0", "9", "13", "14"],
  "11": ["1", "12", "15"],
  "12": ["2", "11", "16"],
  "13": ["10", "14"],
  "14": ["10", "13", "17"],
  "15": ["11", "16", "18"],
  "16": ["12", "15", "19"],
  "17": ["14", "18", "19"],
  "18": ["15", "17"],
  "19": ["16", "17"]
}
EOF

    cat << 'EOF' > /home/user/workspace/reference.json
{
  "ref_means": [4.15, 14.82]
}
EOF

    cat << 'EOF' > /home/user/workspace/network_ode.py
import numpy as np
from scipy.integrate import solve_ivp
import json
import os

def load_graph():
    with open('/home/user/workspace/graph.json', 'r') as f:
        return json.load(f)

def odefunc(t, y, graph):
    dydt = np.zeros_like(y)
    for node, neighbors in graph.items():
        idx = int(node)
        flow = 0.0
        # BUG: non-deterministic iteration order causes float reduction differences
        for n in set(neighbors):
            n_idx = int(n)
            flow += (y[n_idx] - y[idx]) * 0.5
        dydt[idx] = flow
    return dydt

def run_sim():
    graph = load_graph()
    N = len(graph)
    y0 = np.zeros(N)
    y0[0] = 50.0
    y0[19] = 50.0

    # Run ODE solver
    sol = solve_ivp(odefunc, [0, 5], y0, args=(graph,), method='RK45')
    return sol.y[:, -1]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
