#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/deploy.log
INFO: Starting deployment...
INFO: Service A initialization started.
INFO: Service B initialization started.
ERROR: Missing dependency config: Service A not ready.
INFO: Retrying Service B...
ERROR: Missing dependency config: Service A not ready.
INFO: Deployment aborted.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
