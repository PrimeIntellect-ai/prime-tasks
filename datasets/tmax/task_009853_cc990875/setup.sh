#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import csv
import random

random.seed(42)

with open("/home/user/input_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "prior_prob", "likelihood", "evidence", "expected_posterior"])

    for i in range(1, 101):
        prior = random.uniform(0.1, 0.9)
        likelihood = random.uniform(0.1, 0.9)
        evidence = random.uniform(0.1, 0.9)

        # Inject errors
        if i == 15:
            prior = 1.5 # schema error
        elif i == 42:
            evidence = 0.0 # schema error
        elif i == 73:
            prior = -0.2 # schema error

        expected = (likelihood * prior) / evidence if evidence != 0.0 else 0.0

        if i == 55:
            expected += 0.005 # accuracy error

        writer.writerow([i, f"{prior:.6f}", f"{likelihood:.6f}", f"{evidence:.6f}", f"{expected:.6f}"])
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
