#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/deployments/v1
    mkdir -p /home/user/deployments/v2
    mkdir -p /home/user/deployments/v3
    mkdir -p /home/user/archives

    # Create monitor.conf
    cat << 'EOF' > /home/user/monitor.conf
DEPLOY_BASE=/home/user/deployments
CURRENT_LINK=/home/user/app_current
ARCHIVE_DIR=/home/user/archives
EOF

    # Create history.txt
    cat << 'EOF' > /home/user/deployments/history.txt
v1
v2
v3
EOF

    # Create files for v1
    echo "OK" > /home/user/deployments/v1/health.txt
    echo "Log v1: All good" > /home/user/deployments/v1/app.log

    # Create files for v2
    echo "OK" > /home/user/deployments/v2/health.txt
    echo -e "Log v2 start\nERROR: database timeout\nLog v2 end" > /home/user/deployments/v2/app.log

    # Create files for v3
    echo "DEGRADED" > /home/user/deployments/v3/health.txt
    echo "Log v3: startup" > /home/user/deployments/v3/app.log

    # Create symlink
    ln -s /home/user/deployments/v3 /home/user/app_current

    # Set permissions
    chmod -R 777 /home/user
