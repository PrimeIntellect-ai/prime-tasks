#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/exp1.json
{
  "id": "exp_alpha",
  "accuracy": 0.95,
  "loss": 0.1,
  "vector": [1.1, 1.9, 3.1]
}
EOF

    cat << 'EOF' > /home/user/experiments/exp2.json
{
  "id": "exp_beta",
  "accuracy": 0.88,
  "loss": 0.2,
  "vector": [0.0, 0.0, 0.0]
}
EOF

    cat << 'EOF' > /home/user/experiments/exp3.json
{
  "id": "exp_gamma",
  "accuracy": 0.99,
  "vector": [1.0, 2.0, 3.0]
}
EOF

    cat << 'EOF' > /home/user/experiments/exp4.json
{
  "id": "exp_delta",
  "accuracy": 1.2,
  "loss": 0.05,
  "vector": [1.0, 2.0, 3.0]
}
EOF

    cat << 'EOF' > /home/user/experiments/exp5.json
{
  "id": "exp_epsilon",
  "accuracy": 0.91,
  "loss": -0.5,
  "vector": [1.0, 2.0, 3.0]
}
EOF

    cat << 'EOF' > /home/user/experiments/exp6.json
{
  "id": "exp_zeta",
  "accuracy": 0.92,
  "loss": 0.15,
  "vector": [1.5, 2.5, 3.5]
}
EOF

    chmod -R 777 /home/user
