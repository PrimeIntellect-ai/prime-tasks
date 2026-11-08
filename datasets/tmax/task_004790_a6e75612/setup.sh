#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/experiments

    cat <<EOF > /home/user/experiments/exp_target.json
{
  "id": "exp_target",
  "learning_rate": 0.015,
  "batch_size": 64,
  "accuracy": 0.82
}
EOF

    cat <<EOF > /home/user/experiments/exp_1.json
{
  "id": "exp_1",
  "learning_rate": 0.010,
  "batch_size": 128,
  "accuracy": 0.85
}
EOF

    cat <<EOF > /home/user/experiments/exp_2.json
{
  "id": "exp_2",
  "learning_rate": 0.014,
  "batch_size": 64,
  "accuracy": 0.80
}
EOF

    cat <<EOF > /home/user/experiments/exp_3.json
{
  "id": "exp_3",
  "learning_rate": 0.050,
  "batch_size": 32,
  "accuracy": 0.70
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/experiments
    chmod -R 777 /home/user
