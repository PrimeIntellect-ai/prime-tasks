#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network_sim.py
import random

class NetworkSimulation:
    def __init__(self, num_nodes=20, seed=42):
        random.seed(seed)
        self.num_nodes = num_nodes
        self.edges = set()

        # Randomly generate some edges
        for i in range(num_nodes):
            for j in range(i+1, num_nodes):
                if random.random() < 0.3:
                    self.edges.add((i, j, random.uniform(0.1, 5.0)))

        self.capacities = [random.uniform(1.0, 10.0) for _ in range(num_nodes)]
        self.target_capacities = [5.0 for _ in range(num_nodes)]

    def compute_total_loss(self):
        # BUG: Iterating over a set causes non-deterministic reduction order
        edge_loss = sum(weight for u, v, weight in self.edges)

        node_loss = sum((c - t)**2 for c, t in zip(self.capacities, self.target_capacities))
        return edge_loss + node_loss

    def optimize_node_capacities(self, epochs=50, learning_rate=0.05):
        for epoch in range(epochs):
            # TODO: Implement gradient descent step here
            # For each node i:
            # gradient = 2 * (self.capacities[i] - self.target_capacities[i])
            # self.capacities[i] -= learning_rate * gradient
            pass

if __name__ == "__main__":
    sim = NetworkSimulation()
    sim.optimize_node_capacities()
    final_loss = sim.compute_total_loss()
    print(f"Final Loss: {final_loss}")
EOF

    cat << 'EOF' > /home/user/test_sim.py
from network_sim import NetworkSimulation

def test_determinism():
    losses = []
    for _ in range(5):
        sim = NetworkSimulation(seed=100)
        # Hack to trigger hash randomization effects if sets are used directly
        # In actual Python, set iteration order depends on PYTHONHASHSEED
        # But even sorting fixes the logic theoretically.
        # We will test if the calculation is exactly equal
        losses.append(sim.compute_total_loss())

    assert len(set(losses)) == 1, "Loss calculation is not deterministic!"

def test_optimization():
    sim = NetworkSimulation(seed=42)
    initial_loss = sim.compute_total_loss()
    sim.optimize_node_capacities(epochs=10, learning_rate=0.1)
    optimized_loss = sim.compute_total_loss()
    assert optimized_loss < initial_loss, "Optimization did not decrease the loss!"

if __name__ == "__main__":
    test_determinism()
    test_optimization()
    print("All tests passed!")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
