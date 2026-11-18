#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow scipy numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random

random.seed(42)

with open('/home/user/artifacts/raw_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['req_id', 'model', 'y_pred', 'y_true'])

    # model_alpha: 500 rows, 400 correct (80%)
    for i in range(500):
        correct = 1 if i < 400 else 0
        y_true = random.randint(0, 1)
        y_pred = y_true if correct else (1 - y_true)
        writer.writerow([f'req_A_{i}', 'model_alpha', y_pred, y_true])

    # model_beta: 600 rows, 510 correct (85%)
    for i in range(600):
        correct = 1 if i < 510 else 0
        y_true = random.randint(0, 1)
        y_pred = y_true if correct else (1 - y_true)
        writer.writerow([f'req_B_{i}', 'model_beta', y_pred, y_true])

    # Bad rows (Schema violations)
    writer.writerow(['bad_1', 'model_alpha', 'ERROR', '1'])
    writer.writerow(['bad_2', 'model_beta', '0', 'NULL'])
    writer.writerow(['bad_3', '', '1', '1']) # empty model
    writer.writerow(['bad_4', 'model_alpha', '', '0'])
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
