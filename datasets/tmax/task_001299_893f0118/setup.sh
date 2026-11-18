#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/setup_tmp
    cd /home/user/setup_tmp

    # Create log 1
    cat << 'EOF' > log1.log
2023-10-01 10:00:01 [INFO] System startup initiated
2023-10-01 10:00:02 [DEBUG] Loading configuration module
2023-10-01 10:00:03 [ERROR] Failed to load module X
EOF
    tar -cf a.tar log1.log

    # Create log 2 (will be corrupted)
    cat << 'EOF' > log2.log
2023-10-01 10:01:00 [INFO] Entering secondary boot phase
2023-10-01 10:01:05 [DEBUG] Memory check OK
EOF
    tar -cf b.tar log2.log
    # Corrupt b.tar by truncating it
    dd if=/dev/zero of=b.tar bs=1 count=100 seek=50 conv=notrunc

    # Create log 3
    cat << 'EOF' > log3.log
2023-10-01 10:02:00 [WARN] High memory usage detected
2023-10-01 10:02:05 [DEBUG] Garbage collection triggered
2023-10-01 10:02:10 [INFO] System stable
EOF
    tar -cf c.tar log3.log

    # Package everything
    tar -czf /home/user/archive.tar.gz a.tar b.tar c.tar

    # Cleanup
    cd /home/user
    rm -rf /home/user/setup_tmp

    chmod -R 777 /home/user
