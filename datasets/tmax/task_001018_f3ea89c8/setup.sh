#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/operator-repo
    cd /home/user/operator-repo
    git init
    cat << 'EOF' > manifest.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 2
EOF
    git add manifest.yaml
    git config user.name "Test User"
    git config user.email "test@example.com"
    git commit -m "Initial commit"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/operator-repo
    chmod -R 777 /home/user
