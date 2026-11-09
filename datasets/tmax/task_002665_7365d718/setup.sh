#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl tar
    pip3 install pytest

    mkdir -p /home/user/dashboards
    mkdir -p /home/user/certs
    mkdir -p /home/user/metrics

    echo '{"dashboard": "system_overview", "panels": 4}' > /home/user/dashboards/main.json
    echo 'cpu_usage_percent 45.2' > /home/user/metrics/data.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
