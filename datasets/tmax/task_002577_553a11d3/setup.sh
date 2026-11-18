#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/test_data

cat << 'EOF' > /home/user/math_lib.c
int compute_collatz_steps(int n) {
    if (n <= 0) return 0;
    int steps = 0;
    while (n != 1) {
        if (n % 2 == 0) {
            n = n / 2;
        } else {
            n = 3 * n + 1;
        }
        steps++;
    }
    return steps;
}
EOF

cat << 'EOF' > /tmp/setup_data.py
import json
import os

data = [
    (1, 15),
    (2, 27),
    (3, 9),
    (4, 97),
    (5, 12),
    (6, 15),
    (7, 871),
    (8, 9),
    (9, 21),
    (10, 15)
]

for id_val, n_val in data:
    with open(f"/home/user/test_data/test_{id_val}.json", "w") as f:
        json.dump({"id": id_val, "value": n_val}, f)
EOF
python3 /tmp/setup_data.py
rm /tmp/setup_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
