#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc iproute2 jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/legacy_proxy.conf
route_api=18080
route_web=18081
route_metrics=18082
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
