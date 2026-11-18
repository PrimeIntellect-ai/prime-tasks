#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np

os.makedirs("/home/user", exist_ok=True)

np.random.seed(42)
X0_c0 = np.random.normal(0, 1, 50)
X1_c0 = np.random.normal(0, 1, 50)
X0_c1 = np.random.normal(1.5, 1, 50)
X1_c1 = np.random.normal(1.5, 1, 50)

data_c0 = np.column_stack((X0_c0, X1_c0, np.zeros(50)))
data_c1 = np.column_stack((X0_c1, X1_c1, np.ones(50)))

data = np.vstack((data_c0, data_c1))
np.random.shuffle(data)

with open("/home/user/data.csv", "w") as f:
    for row in data:
        f.write(f"{row[0]},{row[1]},{int(row[2])}\n")

epsilons = [0.01, 0.5, 2.0]
best_eps = -1
best_acc = -1

for eps in epsilons:
    correct = 0
    for k in range(5):
        val_start = k * 20
        val_end = (k + 1) * 20

        val_set = data[val_start:val_end]
        train_set = np.vstack((data[:val_start], data[val_end:]))

        models = {}
        for c in [0, 1]:
            c_data = train_set[train_set[:, 2] == c]
            prior = len(c_data) / len(train_set)
            means = np.mean(c_data[:, :2], axis=0)
            vars = np.var(c_data[:, :2], axis=0) + eps
            models[c] = {'prior': prior, 'means': means, 'vars': vars}

        for row in val_set:
            x = row[:2]
            y_true = row[2]

            log_posteriors = {}
            for c in [0, 1]:
                m = models[c]
                lp = np.log(m['prior'])
                for f in range(2):
                    lp -= 0.5 * (np.log(2 * np.pi * m['vars'][f]) + ((x[f] - m['means'][f])**2) / m['vars'][f])
                log_posteriors[c] = lp

            if log_posteriors[1] > log_posteriors[0]:
                y_pred = 1
            else:
                y_pred = 0

            if y_pred == y_true:
                correct += 1

    acc = correct / 100.0
    if acc > best_acc:
        best_acc = acc
        best_eps = eps
    elif acc == best_acc:
        if eps < best_eps:
            best_eps = eps

expected = {"best_epsilon": float(best_eps), "best_accuracy": float(best_acc)}
with open("/home/user/.expected_log.json", "w") as f:
    json.dump(expected, f)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
