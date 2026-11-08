#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    pip3 install matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph.json
{
  "nodes": [0, 1, 2, 3],
  "edges": [[0, 1], [1, 2], [2, 3]],
  "initial_temps": {"0": 100.0, "1": 0.0, "2": 0.0, "3": 10.0},
  "alpha": 0.5
}
EOF

    cat << 'EOF' > /home/user/simulate.py
import json
import math
import matplotlib.pyplot as plt

def compute_derivatives(temps, edges, alpha):
    # Computes dT/dt for the graph using a simple Laplacian
    dT = {node: 0.0 for node in temps}
    degree = {node: 0 for node in temps}

    for u, v in edges:
        dT[u] += temps[v] - temps[u]
        dT[v] += temps[u] - temps[v]
        degree[u] += 1
        degree[v] += 1

    for node in temps:
        dT[node] *= alpha
    return dT

def step_euler(temps, edges, alpha, dt):
    dT = compute_derivatives(temps, edges, alpha)
    return {node: temps[node] + dT[node] * dt for node in temps}

def adaptive_integrate(nodes, edges, initial_temps, alpha, T_end):
    temps = initial_temps.copy()
    t = 0.0
    dt = 0.1
    tol = 1e-4

    while t < T_end:
        if t + dt > T_end:
            dt = T_end - t

        # Full step
        temps_full = step_euler(temps, edges, alpha, dt)

        # Two half steps
        temps_half_1 = step_euler(temps, edges, alpha, dt / 2)
        temps_half_2 = step_euler(temps_half_1, edges, alpha, dt / 2)

        # Estimate error
        error = max(abs(temps_full[n] - temps_half_2[n]) for n in nodes)

        if error > tol:
            # BUG IS HERE:
            dt = dt * 2.0  # Should be dt = dt / 2.0
            continue

        temps = temps_half_2
        t += dt

        # Increase step size if error is very small
        if error < tol / 10:
            dt *= 1.5

    return temps

def refine_mesh(nodes, edges, initial_temps):
    """
    TODO: Implement mesh refinement.
    For each edge, add a midpoint node.
    Return updated nodes, edges, initial_temps.
    """
    pass

if __name__ == "__main__":
    with open("/home/user/graph.json", "r") as f:
        data = json.load(f)

    nodes = data["nodes"]
    edges = data["edges"]
    initial_temps = {int(k): v for k, v in data["initial_temps"].items()}
    alpha = data["alpha"]

    # nodes, edges, initial_temps = refine_mesh(nodes, edges, initial_temps)

    # final_temps = adaptive_integrate(nodes, edges, initial_temps, alpha, 0.5)

    # TODO: Save final_temps to /home/user/final_temperatures.json
    # TODO: Plot Final Temperatures and save to /home/user/thermal_plot.png
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
