#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest

    mkdir -p /home/user/operator

    # Create the dummy cert and key for TLS
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/operator/key.pem -out /home/user/operator/cert.pem -days 365 -nodes -subj "/CN=localhost" 2>/dev/null

    # Create the corrupted log file
    cat << 'EOF' > /home/user/operator/cron_out.log
[2023-10-24 10:00:01] ERROR: envsubst not found in PATH=/usr/bin:/bin.
[2023-10-24 10:00:01] Fallback dump:
RAW_MANIFEST_START
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
RAW_MANIFEST_END
[2023-10-24 10:05:01] ERROR: envsubst not found in PATH=/usr/bin:/bin.
[2023-10-24 10:05:01] Fallback dump:
RAW_MANIFEST_START
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
RAW_MANIFEST_END
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
