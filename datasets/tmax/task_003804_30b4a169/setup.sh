#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create app.log
    cat << 'EOF' > /home/user/app.log
System initialized.
User login: AKIA1234567890ABCDEF success.
Connecting to backend.
Error: AKIAZZZZZZZZZZZZZZZZ invalid permissions.
Processing batch 1.
EOF

    # Create mem.dmp
    echo "06001d120311117f0d2e261127213071361276313163" > /home/user/mem.dmp

    chmod -R 777 /home/user
