#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy networkx scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/run_diffusion.py
import numpy as np
import networkx as nx
from scipy.integrate import solve_ivp
import multiprocessing
import json

def simulate_graph(seed):
    np.random.seed(seed)
    # Generate random graph
    G = nx.erdos_renyi_graph(50, 0.4, seed=seed)
    L = nx.laplacian_matrix(G).toarray()

    def deriv(t, x):
        return -1000.0 * L.dot(x)

    x0 = np.random.rand(50)

    # Warning: RK45 struggles with stiff systems
    sol = solve_ivp(deriv, [0, 1.0], x0, method='RK45')

    final_x = sol.y[:, -1]
    numerical_mean = final_x.mean()
    analytical_mean = x0.mean()

    # TO DO: add analytical solution validation (assert numerical_mean is close to analytical_mean)

    return str(seed), analytical_mean

if __name__ == "__main__":
    seeds = [1, 2, 3, 4]

    # TO DO: parallelize this with multiprocessing.Pool(4)
    results = {}
    for s in seeds:
        k, v = simulate_graph(s)
        results[k] = v

    with open('/home/user/steady_states.json', 'w') as f:
        json.dump(results, f, indent=4)
EOF
    chmod +x /home/user/run_diffusion.py

    chmod -R 777 /home/user
