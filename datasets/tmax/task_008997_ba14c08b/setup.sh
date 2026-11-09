#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    mkdir -p /home/user/mlops_workspace
    cat << 'EOF' > /home/user/mlops_workspace/corpus.json
[
  "Machine learning is a field of artificial intelligence.",
  "Deep learning is a subset of machine learning based on artificial neural networks.",
  "Machine learning is a branch of artificial intelligence.",
  "The quick brown fox jumps over the lazy dog.",
  "A fast brown fox leaps over a sleeping dog.",
  "Data science involves extracting insights from messy data.",
  "Data engineering is about building data pipelines.",
  "Artificial intelligence encompasses machine learning and deep learning.",
  "Reinforcement learning trains agents to maximize reward.",
  "Unsupervised learning finds hidden patterns in unlabeled data.",
  "Semi-supervised learning uses a small amount of labeled data with a large amount of unlabeled data.",
  "Data science is about extracting meaningful insights from data."
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
