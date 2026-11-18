#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create initial state
    mkdir -p /home/user/app_data
    echo "MODE=PRODUCTION" > /home/user/app_data/config.txt

    cat << 'EOF' > /home/user/build_history.txt
build_id=101 version=1.0.0 status=SUCCESS
build_id=102 version=1.1.0 status=FAILED
build_id=103 version=1.2.0 status=SUCCESS
build_id=104 version=2.0.0 status=PENDING
EOF

    cat << 'EOF' > /home/user/vmounts.fstab
/home/user/app_data /home/user/mnt_target bind 0 0
EOF

    chmod -R 777 /home/user
