#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create required directories
    mkdir -p /home/user/departments/engineering
    mkdir -p /home/user/departments/sales
    mkdir -p /home/user/departments/hr
    mkdir -p /home/user/global_share

    # Create accounts.txt
    cat << 'EOF' > /home/user/accounts.txt
alice:engineering:101
bob:sales:102
charlie:engineering:103
diana:hr:104
EOF

    # Create custom_fstab
    cat << 'EOF' > /home/user/custom_fstab
/dev/sda1 / ext4 defaults 1 1
# Other system mounts
/dev/sdb1 /home ext4 defaults 1 2
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
