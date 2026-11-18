#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests
    head -c 5000 /dev/urandom | base64 > /home/user/manifests/deployment.yaml
    head -c 2000 /dev/urandom | base64 > /home/user/manifests/service.yaml
    head -c 1000 /dev/urandom | base64 > /home/user/manifests/config.txt

    echo 'python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &' >> /home/user/.bashrc
    echo 'python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &' >> /root/.bashrc

    chmod -R 777 /home/user
