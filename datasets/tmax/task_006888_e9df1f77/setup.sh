#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc
    pip3 install pytest matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/run_experiment.py
import json
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt

def run():
    acc = 0.865
    loss = 0.23

    with open('/home/user/results.json', 'w') as f:
        json.dump({'accuracy': acc, 'loss': loss}, f)

    plt.figure()
    plt.plot([1, 2, 3], [0.8, 0.85, acc])
    plt.title(f"Final Accuracy: {acc}")
    plt.savefig('/home/user/plot.png')

if __name__ == '__main__':
    run()
EOF

    chmod -R 777 /home/user
