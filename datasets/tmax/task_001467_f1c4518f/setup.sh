#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mcmc_sim.py
import random
import math

# Do not change the seed!
random.seed(42)

# Dataset with extreme values designed to cause floating point cancellation if summed naively
data = [1e16, 2.5, -1e16, 3.5, 1e16, -1e16, 1.2, -1e16, 1e16]

def log_likelihood(mu):
    # Unstable reduction
    data_sum = sum(data)

    # Likelihood of mu given the data sum, assuming data_sum ~ N(mu, 1)
    return -0.5 * (mu - data_sum)**2

def run_mcmc(iters=5000):
    mu_current = 0.0
    samples = []
    for i in range(iters):
        mu_proposal = mu_current + random.gauss(0, 1.0)

        log_prob_current = log_likelihood(mu_current)
        log_prob_proposal = log_likelihood(mu_proposal)

        # Metropolis-Hastings acceptance ratio
        accept_prob = math.exp(min(0.0, log_prob_proposal - log_prob_current))

        if random.random() < accept_prob:
            mu_current = mu_proposal

        samples.append(mu_current)
    return samples

if __name__ == "__main__":
    samples = run_mcmc()
    with open("/home/user/posterior.txt", "w") as f:
        for s in samples:
            f.write(f"{s}\n")
EOF

    cat << 'EOF' > /home/user/generate_ground_truth.py
import random
import math

random.seed(123)
data = [1e16, 2.5, -1e16, 3.5, 1e16, -1e16, 1.2, -1e16, 1e16]

def log_likelihood(mu):
    data_sum = math.fsum(data) # Stable reduction
    return -0.5 * (mu - data_sum)**2

def run_mcmc(iters=5000):
    mu_current = 0.0
    samples = []
    for i in range(iters):
        mu_proposal = mu_current + random.gauss(0, 1.0)
        log_prob_current = log_likelihood(mu_current)
        log_prob_proposal = log_likelihood(mu_proposal)
        accept_prob = math.exp(min(0.0, log_prob_proposal - log_prob_current))
        if random.random() < accept_prob:
            mu_current = mu_proposal
        samples.append(mu_current)
    return samples

samples = run_mcmc()
with open("/home/user/ground_truth.txt", "w") as f:
    for s in samples:
        f.write(f"{s}\n")
EOF

    python3 /home/user/generate_ground_truth.py
    rm /home/user/generate_ground_truth.py

    chmod -R 777 /home/user
