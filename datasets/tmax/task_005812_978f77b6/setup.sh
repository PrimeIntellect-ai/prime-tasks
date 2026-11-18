#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest numpy

    mkdir -p /home/user/analytics
    cd /home/user/analytics
    git init
    git config user.email "devops@example.com"
    git config user.name "DevOps"

    echo "# Analytics Repo" > README.md
    git add README.md
    git commit -m "Initial commit"

    echo 'DB_PASS="pA55w0rd_xyz789"' > config.py
    git add config.py
    git commit -m "Add database configuration"

    git rm config.py
    git commit -m "Remove hardcoded credentials"

    cat << 'EOF' > score.py
import numpy as np

def softmax(x):
    # Naive implementation susceptible to overflow
    return np.exp(x) / np.sum(np.exp(x))

if __name__ == "__main__":
    data = np.array([1000.0, 1001.0, 1002.0])
    result = softmax(data)
    print(result)
EOF
    git add score.py
    git commit -m "Add scoring function"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
