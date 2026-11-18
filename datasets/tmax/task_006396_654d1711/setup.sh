#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deploy/default
    mkdir -p /home/user/deploy/system
    mkdir -p /home/user/deploy/monitoring

    cat << 'EOF' > /home/user/k8s_fstab
default /home/user/deploy/default fuse.bind rw,nosuid,nodev 0 0
kube-system /home/user/deploy/system fuse.bind rw,nosuid,nodev 0 0
monitoring /home/user/deploy/monitoring fuse.bind rw,nosuid,nodev 0 0
EOF

    git init --bare /home/user/manifests.git

    chmod -R 777 /home/user
