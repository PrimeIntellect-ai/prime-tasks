#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pyyaml

useradd -m -s /bin/bash user || true

mkdir -p /home/user/k8s-operator/incoming
mkdir -p /home/user/k8s-operator/active
mkdir -p /home/user/k8s-operator/backups
mkdir -p /home/user/k8s-operator/config

cat << 'EOF' > /home/user/k8s-operator/config/operator.ini
[settings]
timezone = Asia/Tokyo
backup_format = tar.gz
EOF

cat << 'EOF' > /home/user/k8s-operator/active/app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
EOF

cat << 'EOF' > /home/user/k8s-operator/incoming/app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
EOF

cat << 'EOF' > /home/user/k8s-operator/incoming/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
  - port: 80
EOF

chmod -R 777 /home/user
