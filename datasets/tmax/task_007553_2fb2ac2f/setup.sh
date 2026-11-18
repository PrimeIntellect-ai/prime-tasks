#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    python3 -c '
import random
random.seed(123)
with open("/home/user/run_A.csv", "w") as f:
    for _ in range(10000):
        y_true = random.uniform(0, 100)
        y_pred = y_true + random.gauss(0, 5)
        f.write(f"{y_true:.4f},{y_pred:.4f}\n")

random.seed(456)
with open("/home/user/run_B.csv", "w") as f:
    for _ in range(10000):
        y_true = random.uniform(0, 100)
        y_pred = y_true + random.gauss(0, 8)
        f.write(f"{y_true:.4f},{y_pred:.4f}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
