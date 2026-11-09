#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar grep gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/active_manifests
    mkdir -p /home/user/incoming_manifests
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/active_manifests/old-config.yaml
kind: ConfigMap
metadata:
  name: old-map
data:
  key: value
EOF

    cat << 'EOF' > /home/user/incoming_manifests/pv-data.yaml
kind: PersistentVolume
metadata:
  name: db-volume
spec:
  hostPath:
    path: /home/user/raw_data
EOF

    cat << 'EOF' > /home/user/incoming_manifests/svc-web.yaml
kind: Service
metadata:
  name: web-svc
spec:
  ports:
    - protocol: TCP
      nodePort: 30080
EOF

    cat << 'EOF' > /home/user/incoming_manifests/svc-api.yaml
kind: Service
metadata:
  name: api-svc
spec:
  ports:
    - protocol: TCP
      nodePort: 30443
EOF

    chown -R user:user /home/user/active_manifests /home/user/incoming_manifests /home/user/backups
    chmod -R 777 /home/user
