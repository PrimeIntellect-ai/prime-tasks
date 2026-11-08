#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import math

np.random.seed(42)
n_samples = 100
f1_0 = np.random.normal(0, 1, n_samples)
f2_0 = np.random.normal(0, 1, n_samples)
f1_1 = np.random.normal(3, 1, n_samples)
f2_1 = np.random.normal(3, 1, n_samples)

with open("/home/user/data.csv", "w") as f:
    f.write("f1,f2,label\n")
    for i in range(n_samples):
        f.write(f"{f1_0[i]:.4f},{f2_0[i]:.4f},0\n")
    for i in range(n_samples):
        f.write(f"{f1_1[i]:.4f},{f2_1[i]:.4f},1\n")

# Calculate Ground Truth
q_f1, q_f2 = 1.5, 2.0

mean_f1_0, var_f1_0 = np.mean(f1_0), np.var(f1_0)
mean_f2_0, var_f2_0 = np.mean(f2_0), np.var(f2_0)

mean_f1_1, var_f1_1 = np.mean(f1_1), np.var(f1_1)
mean_f2_1, var_f2_1 = np.mean(f2_1), np.var(f2_1)

def gaussian_pdf(x, mean, var):
    return (1.0 / np.sqrt(2 * np.pi * var)) * np.exp(-((x - mean)**2) / (2 * var))

p_q_given_0 = gaussian_pdf(q_f1, mean_f1_0, var_f1_0) * gaussian_pdf(q_f2, mean_f2_0, var_f2_0)
p_q_given_1 = gaussian_pdf(q_f1, mean_f1_1, var_f1_1) * gaussian_pdf(q_f2, mean_f2_1, var_f2_1)

# Priors are 0.5
p_1_given_q = (p_q_given_1 * 0.5) / (p_q_given_0 * 0.5 + p_q_given_1 * 0.5)

f1_all = np.concatenate([f1_0, f1_1])
f2_all = np.concatenate([f2_0, f2_1])
distances = np.sqrt((f1_all - q_f1)**2 + (f2_all - q_f2)**2)
nearest_idx = np.argmin(distances)

expected_output = f"Probability Class 1: {p_1_given_q:.4f}\nNearest Neighbor Index: {nearest_idx}\n"
with open("/home/user/.truth.txt", "w") as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
