#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments/run_alpha
    mkdir -p /home/user/experiments/run_beta
    mkdir -p /home/user/experiments/run_gamma

    # Run Alpha
    echo '{"learning_rate": 0.01, "batch_size": 32}' > /home/user/experiments/run_alpha/config.json
    echo "epoch,loss,accuracy\n1,0.9,0.55\n2,0.7,0.65\n3,0.5,0.78" > /home/user/experiments/run_alpha/metrics.csv
    head -c 1024 </dev/urandom > /home/user/experiments/run_alpha/model.pt

    # Run Beta
    echo '{"learning_rate": 0.001, "batch_size": 64}' > /home/user/experiments/run_beta/config.json
    echo "epoch,loss,accuracy\n1,0.8,0.60\n2,0.6,0.72\n3,0.4,0.85\n4,0.3,0.89" > /home/user/experiments/run_beta/metrics.csv
    head -c 2048 </dev/urandom > /home/user/experiments/run_beta/model.pt

    # Run Gamma
    echo '{"learning_rate": 0.005, "batch_size": 16}' > /home/user/experiments/run_gamma/config.json
    echo "epoch,loss,accuracy\n1,0.85,0.58\n2,0.65,0.70\n3,0.45,0.82" > /home/user/experiments/run_gamma/metrics.csv
    head -c 1536 </dev/urandom > /home/user/experiments/run_gamma/model.pt

    # Fix echo interpretation of \n
    sed -i 's/\\n/\n/g' /home/user/experiments/run_alpha/metrics.csv
    sed -i 's/\\n/\n/g' /home/user/experiments/run_beta/metrics.csv
    sed -i 's/\\n/\n/g' /home/user/experiments/run_gamma/metrics.csv

    chown -R user:user /home/user/experiments
    chmod -R 777 /home/user
