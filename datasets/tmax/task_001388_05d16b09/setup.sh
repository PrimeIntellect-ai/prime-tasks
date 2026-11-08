#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifests/stage1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-stage1
spec:
  template:
    spec:
      containers:
      - name: app
        image: myregistry.local/frontend:v1.0
EOF

    cat << 'EOF' > /home/user/manifests/stage2.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-stage2
spec:
  template:
    spec:
      containers:
      - name: app
        image: myregistry.local/frontend:v1.0
EOF

    cat << 'EOF' > /home/user/manifests/stage3.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-stage3
spec:
  template:
    spec:
      containers:
      - name: app
        image: myregistry.local/frontend:v1.0
EOF

    cat << 'EOF' > /home/user/monitoring.log
2023-10-01 10:00:01 INFO [stage1] Service started successfully.
2023-10-01 10:05:00 INFO [stage1] CPU usage normal.
2023-10-01 10:10:00 INFO [stage2] Service started successfully.
2023-10-01 10:15:00 WARN [stage2] Memory usage slightly high.
2023-10-01 10:20:00 INFO [stage3] Service started successfully.
2023-10-01 10:25:00 CRITICAL [stage3] Database connection timed out!
2023-10-01 10:30:00 INFO [stage3] Attempting retry.
EOF

    chmod -R 777 /home/user
