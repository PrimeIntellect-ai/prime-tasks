#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import csv

data = []
alphas = [0.1, 0.5, 1.0]

with open('/home/user/predictions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['run_id', 'fold', 'alpha', 'y_true', 'y_pred'])

    run_id = 1
    for alpha in alphas:
        for fold in range(1, 4):
            for i in range(4):
                if alpha == 0.1:
                    y_true = 1.0
                    y_pred = 0.8
                elif alpha == 0.5:
                    if i % 2 == 0:
                        y_true = 1.0
                        y_pred = 0.9
                    else:
                        y_true = 1.0
                        y_pred = 0.8585786
                elif alpha == 1.0:
                    y_true = 1.0
                    y_pred = 0.717157
                writer.writerow([run_id, fold, alpha, y_true, y_pred])
        run_id += 1
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
