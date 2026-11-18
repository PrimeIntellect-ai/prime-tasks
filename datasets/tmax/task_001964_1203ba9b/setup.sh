#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/repo/groupA /home/user/repo/groupB /home/user/repo/groupC/deep

    # Create binary artifacts
    # 1. Meets both criteria: > 100KB and modified before 2023-01-01
    dd if=/dev/urandom of=/home/user/repo/groupA/artifact1.bin bs=1024 count=150 status=none
    touch -d "2022-12-01 12:00:00" /home/user/repo/groupA/artifact1.bin

    # 2. Fails size criterion (only 50KB), meets date criterion
    dd if=/dev/urandom of=/home/user/repo/groupA/artifact2.bin bs=1024 count=50 status=none
    touch -d "2022-12-01 12:00:00" /home/user/repo/groupA/artifact2.bin

    # 3. Meets size criterion, fails date criterion (modified in 2023)
    dd if=/dev/urandom of=/home/user/repo/groupB/artifact3.bin bs=1024 count=150 status=none
    touch -d "2023-06-01 12:00:00" /home/user/repo/groupB/artifact3.bin

    # 4. Meets both criteria, deep in directory tree
    dd if=/dev/urandom of=/home/user/repo/groupC/deep/module.bin bs=1024 count=200 status=none
    touch -d "2020-05-15 08:30:00" /home/user/repo/groupC/deep/module.bin

    # Create configuration files
    cat << 'EOF' > /home/user/repo/groupA/config.conf
id: alpha-99
backend: legacy-storage
version: 1.0
EOF

    cat << 'EOF' > /home/user/repo/groupB/settings.conf
name: module_b
id: beta-42
backend: legacy-storage
version: 2.1
EOF

    cat << 'EOF' > /home/user/repo/groupC/deep/app.conf
id: delta-05
description: core app
backend: legacy-storage
EOF

    # Create a text file that has the matching text but is NOT a .conf file
    cat << 'EOF' > /home/user/repo/groupB/ignore.txt
id: gamma-00
backend: legacy-storage
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
