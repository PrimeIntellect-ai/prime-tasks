#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl tar
    pip3 install pytest

    mkdir -p /home/user/manifests
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/manifests/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
EOF

    cat << 'EOF' > /home/user/manifests/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: test-svc
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
