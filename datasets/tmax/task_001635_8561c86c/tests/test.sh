#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import glob
import subprocess
import pytest
import numpy as np
import networkx as nx

def generate_truth(graph_file, out_file):
    G = nx.read_edgelist(graph_file, nodetype=int)
    n = max(G.nodes()) + 1
    L = nx.laplacian_matrix(G, nodelist=range(n)).toarray()

    dt = 0.01
    steps = 1000
    omega = 3.142  # Agent is expected to use 3.142 (or close to pi)
    x = np.zeros(n)

    for step in range(steps):
        t = step * dt
        drift = - L.dot(x)
        drift[0] += np.sin(omega * t)
        x = x + drift * dt

    np.savetxt(out_file, x, delimiter=',')

def test_final_expected_values():
    # 1. Find the agent's script
    scripts = glob.glob('/home/user/solve_expected.*')
    assert len(scripts) > 0, "Could not find any script named solve_expected.* in /home/user/"
    script_path = scripts[0]

    # 2. Create a secret test graph
    graph_file = '/tmp/test_graph.txt'
    agent_out_file = '/home/user/agent_out.csv'
    truth_out_file = '/tmp/truth_out.csv'

    # Generate a connected graph to ensure non-trivial diffusion
    G = nx.erdos_renyi_graph(30, 0.2, seed=1337)
    nx.write_edgelist(G, graph_file, data=False)

    # 3. Run the agent's script
    if script_path.endswith('.py'):
        cmd = [sys.executable, script_path, graph_file, agent_out_file]
    elif script_path.endswith('.sh'):
        cmd = ['bash', script_path, graph_file, agent_out_file]
    else:
        # Fallback for compiled or executable scripts
        cmd = [script_path, graph_file, agent_out_file]
        if not os.access(script_path, os.X_OK):
            os.chmod(script_path, 0o755)

    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Agent script failed with exit code {e.returncode}.\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}")

    assert os.path.exists(agent_out_file), f"Agent script did not produce the expected output file at {agent_out_file}"

    # 4. Generate truth and compare
    generate_truth(graph_file, truth_out_file)

    try:
        agent_data = np.loadtxt(agent_out_file, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load agent output file as CSV: {e}")

    truth_data = np.loadtxt(truth_out_file, delimiter=',')

    assert agent_data.shape == truth_data.shape, f"Shape mismatch: agent {agent_data.shape} vs truth {truth_data.shape}"

    mse = np.mean((agent_data - truth_data)**2)
    threshold = 1e-4

    assert mse < threshold, f"MSE {mse:.6e} is not strictly less than the threshold {threshold}. Agent values do not match expected Euler-Maruyama integration with omega~=3.142."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
