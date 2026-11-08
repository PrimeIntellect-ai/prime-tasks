#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_data.py
import json
import numpy as np
from scipy.integrate import odeint

np.random.seed(100)
alpha_true = 2.5
beta_true = 0.5

def model(C, t, alpha, beta):
    return alpha - beta * C

data = {}
for i in range(20):
    seq_name = f"seq_{i}"
    t = np.linspace(0, 10, 50)
    C_true = odeint(model, 0, t, args=(alpha_true, beta_true)).flatten()
    C_noisy = C_true + np.random.normal(0, 0.5, size=len(t))
    data[seq_name] = {"t": t.tolist(), "c": C_noisy.tolist()}

with open("/home/user/protein_data.json", "w") as f:
    json.dump(data, f)
EOF

    python3 /home/user/create_data.py

    cat << 'EOF' > /home/user/fit_mcmc.py
import json
import numpy as np
from scipy.integrate import odeint

def model(C, t, alpha, beta):
    return alpha - beta * C

def log_likelihood(alpha, beta, data):
    if alpha < 0 or beta < 0:
        return -np.inf

    total_error = 0.0
    # BUG: Iterating over a set causes non-deterministic order.
    unique_seqs = set(data.keys())
    for seq in unique_seqs:
        t = np.array(data[seq]['t'])
        c_obs = np.array(data[seq]['c'])
        c_pred = odeint(model, 0, t, args=(alpha, beta)).flatten()
        total_error += np.sum((c_obs - c_pred)**2)

    return -0.5 * total_error

def run_mcmc():
    np.random.seed(42)
    with open("/home/user/protein_data.json", "r") as f:
        data = json.load(f)

    n_steps = 1500
    alpha_current, beta_current = 1.0, 1.0
    ll_current = log_likelihood(alpha_current, beta_current, data)

    chain = []

    for _ in range(n_steps):
        alpha_prop = alpha_current + np.random.normal(0, 0.1)
        beta_prop = beta_current + np.random.normal(0, 0.05)

        ll_prop = log_likelihood(alpha_prop, beta_prop, data)

        if np.log(np.random.uniform()) < (ll_prop - ll_current):
            alpha_current = alpha_prop
            beta_current = beta_prop
            ll_current = ll_prop

        chain.append([alpha_current, beta_current])

    chain = np.array(chain[500:]) # Burn-in

    mean_alpha = np.mean(chain[:, 0])
    mean_beta = np.mean(chain[:, 1])

    with open("/home/user/posterior_results.txt", "w") as f:
        f.write(f"alpha: {mean_alpha:.4f}, beta: {mean_beta:.4f}\n")
    print("Results saved to /home/user/posterior_results.txt")

if __name__ == "__main__":
    run_mcmc()
EOF

    chmod -R 777 /home/user
