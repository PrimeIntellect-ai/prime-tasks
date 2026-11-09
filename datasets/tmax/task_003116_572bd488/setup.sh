#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/bin /home/user/manifests /home/user/logs
    touch /home/user/manifests/deployment.yaml
    touch /home/user/manifests/service.yaml
    touch /home/user/manifests/ingress.yaml

    chmod -R 777 /home/user
