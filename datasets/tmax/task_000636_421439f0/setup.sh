#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional required packages
    apt-get install -y git g++

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /home/user/logs
    mkdir -p /home/user/build_env

    # Create raw log file
    cat << 'EOF' > /home/user/logs/qemu_raw.log
[2023-10-01T12:00:00Z] START VM_ID=101 CMD="qemu-system-x86_64 -m 1024 -vnc 192.168.1.50:5901"
[2023-10-01T12:05:00Z] STOP VM_ID=101
[2023-10-01T12:10:00Z] START VM_ID=102 CMD="qemu-system-aarch64 -m 2048 -vnc 10.0.0.5:5902 -daemonize"
[2023-10-01T12:15:00Z] ERROR VM_ID=103 FAILED TO START
[2023-10-01T12:20:00Z] START VM_ID=104 CMD="qemu-system-x86_64 -vnc 127.0.0.1:5900 -monitor stdio"
EOF

    # Set permissions
    chmod -R 777 /home/user
