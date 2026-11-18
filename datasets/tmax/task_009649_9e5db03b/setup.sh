#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/system.log
[2023-10-27 10:00:00] System start
[2023-10-27 10:01:00] Training initialized
[2023-10-27 10:05:00] Metric alert triggered
EOF

    cat << 'EOF' > /home/user/app/runner.py
import time
import os

log_path = '/home/user/app/training.log'
with open(log_path, 'w') as f:
    f.write("[2023-10-27 10:01:05] Loss: 10.5\n")
    f.write("[2023-10-27 10:02:10] Loss: 25.2\n")
    f.write("[2023-10-27 10:03:15] Loss: 65.8\n")
    f.write("[2023-10-27 10:04:20] Loss: 150.4\n")
    f.write("[2023-10-27 10:05:25] Loss: 340.9\n")
    f.flush()

    # Delete the file but keep it open
    os.remove(log_path)

    while True:
        time.sleep(1)
EOF

    cat << 'EOF' > /home/user/app/train.py
def compute_loss(x):
    return (x - 3.0) ** 2

def compute_gradient(x):
    return 2 * (x - 3.0)

def train():
    x = 10.0
    learning_rate = 0.1
    for epoch in range(50):
        loss = compute_loss(x)
        grad = compute_gradient(x)

        # BUG: Diverging update rule (adding gradient instead of subtracting)
        x = x + learning_rate * grad

    print(f"Final x: {x:.4f}")

if __name__ == "__main__":
    train()
EOF

    echo "python3 /home/user/app/runner.py &" >> /home/user/.bashrc
    echo "sleep 1" >> /home/user/.bashrc

    chmod -R 777 /home/user
