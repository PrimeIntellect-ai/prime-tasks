#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest matplotlib pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/make_data.py
import csv
import math

true_theta = 0.5
t_vals = [0, 1, 2, 3, 4, 5]
data = [{"t": t, "x": 10.0 * math.exp(-true_theta * t)} for t in t_vals]

with open('/home/user/data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["t", "x"])
    writer.writeheader()
    writer.writerows(data)
EOF
    python3 /tmp/make_data.py
    rm /tmp/make_data.py

    cat << 'EOF' > /home/user/mcmc_ode.py
import csv
import math
import random

def solve_ode(theta, t_max):
    # Euler method
    dt = 2.0 # BUG IS HERE, should be changed to 0.1
    t = 0.0
    x = 10.0
    res = {0.0: x}
    while t < t_max:
        x = x - theta * x * dt
        t += dt
        # Store nearest integer times
        for target in range(1, int(t_max) + 1):
            if abs(t - target) < dt/2:
                res[float(target)] = x
    return res

def log_likelihood(theta, data):
    if theta <= 0: return -1e9
    preds = solve_ode(theta, 5.0)
    ll = 0.0
    for row in data:
        t = float(row['t'])
        obs = float(row['x'])
        pred = preds.get(t, obs)
        ll -= 0.5 * ((obs - pred)/0.5)**2
    return ll

def main():
    random.seed(42)
    data = []
    with open('/home/user/data.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)

    samples = []
    current_theta = 0.2
    current_ll = log_likelihood(current_theta, data)

    for _ in range(2500):
        prop_theta = current_theta + random.gauss(0, 0.05)
        prop_ll = log_likelihood(prop_theta, data)

        if math.log(random.random()) < prop_ll - current_ll:
            current_theta = prop_theta
            current_ll = prop_ll

        samples.append(current_theta)

    with open('trace.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["theta"])
        for s in samples:
            writer.writerow([s])

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
