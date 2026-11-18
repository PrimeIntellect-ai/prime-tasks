#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/run_1.json
{
  "run_id": "run_001",
  "description": "Baseline CNN for image classification.",
  "metrics": {"accuracy": 0.85, "loss": 0.4}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_2.json
{
  "run_id": "run_002",
  "description": "Optimized deep neural network for image classification using ResNet.",
  "metrics": {"accuracy": 0.95, "loss": 0.1}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_3.json
{
  "run_id": "run_003",
  "description": "Super fast image model.",
  "metrics": {"accuracy": 1.05, "loss": 0.05}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_4.json
{
  "run_id": "run_004",
  "description": "Text classification baseline.",
  "metrics": {"accuracy": 0.70}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_5.json
{
  "run_id": "run_005",
  "description": "Deep neural network for text processing.",
  "metrics": {"accuracy": 0.88, "loss": 0.3}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_6.json
{
  "run_id": "run_006",
  "description": "Optimized deep neural network for image classification.",
  "metrics": {"accuracy": 0.92, "loss": 0.2}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_7.json
{
  "run_id": "run_007",
  "description": "Simple linear regression model.",
  "metrics": {"accuracy": 0.50, "loss": 1.5}
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_8.json
{
  "run_id": "run_008",
  "description": "Another optimized deep neural network for image classification.",
  "metrics": {"accuracy": 0.91, "loss": -0.1}
}
EOF

    chmod -R 777 /home/user
