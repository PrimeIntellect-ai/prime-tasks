#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata tar gzip
    pip3 install pytest pyyaml pytz

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifests/deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  annotations:
    deployed-at: "2023-11-01 08:30:00 UTC"
spec:
  replicas: 3
EOF

    cat << 'EOF' > /home/user/manifests/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  annotations:
    deployed-at: "2023-11-01 09:15:00 UTC"
spec:
  ports:
    - port: 80
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
