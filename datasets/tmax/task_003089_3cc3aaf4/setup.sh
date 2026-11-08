#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests
    mkdir -p /home/user/processed_manifests

    cat << 'EOF' > /home/user/manifests/cluster-alpha.yaml
apiVersion: custom.k8s.io/v1
kind: ClusterNetwork
metadata:
  name: alpha-net
spec:
  podCIDR: 10.244.0.0/16
  gateway: 10.96.0.1
EOF

    cat << 'EOF' > /home/user/manifests/cluster-beta.yaml
apiVersion: custom.k8s.io/v1
kind: ClusterNetwork
metadata:
  name: beta-net
spec:
  podCIDR: 192.168.50.0/24
  gateway: 10.96.0.1
EOF

    chmod -R 777 /home/user
