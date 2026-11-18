#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create necessary directories and files
    mkdir -p /home/user/app_data/
    echo "critical_metric_value: 42" > /home/user/app_data/metrics.txt

    # Set permissions
    chmod -R 777 /home/user
