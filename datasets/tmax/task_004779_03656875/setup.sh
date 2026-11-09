#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gnuplot
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import numpy as np

true_A = 5.0
true_k = 0.2
t = np.linspace(0, 20, 100)
rate = true_A * true_k * np.exp(-true_k * t)

np.random.seed(42)
noise = np.random.normal(0, 0.001, size=t.shape)
rate_noisy = rate + noise

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/reaction_rate.csv", "w") as f:
    f.write("Time,Rate\n")
    for i in range(len(t)):
        f.write(f"{t[i]},{rate_noisy[i]}\n")
'

    chmod -R 777 /home/user
