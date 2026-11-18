#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/art1.meta
name: package_A
architecture: x86_64
version: 1.0.1
status: pending
EOF

    cat << 'EOF' > /home/user/artifacts/art2.meta
name: package_B
architecture: arm64
version: 2.1.0
status: pending
EOF

    cat << 'EOF' > /home/user/artifacts/art3.meta
name: package_C
architecture: x86_64
version: 3.0.0
status: curated
EOF

    cat << 'EOF' > /home/user/artifacts/art4.meta
name: package_D
architecture: x86_64
version: 1.1.5
status: pending
EOF

    # Create some dummy binaries
    dd if=/dev/urandom of=/home/user/artifacts/art1.bin bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=/home/user/artifacts/art2.bin bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=/home/user/artifacts/art3.bin bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of=/home/user/artifacts/art4.bin bs=1K count=1 2>/dev/null

    # Create initial full backup and snapshot
    tar --listed-incremental=/home/user/snapshot.snar -cf /home/user/backup_full.tar /home/user/artifacts

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
