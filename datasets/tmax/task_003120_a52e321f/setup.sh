#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create net_status.txt
    cat << 'EOF' > /home/user/net_status.txt
web01 - REACHABLE
db01 - REACHABLE
cache01 - TIMEOUT
app01 - REACHABLE
app02 - TIMEOUT
legacy01 - REACHABLE
EOF

    # Create qemu_procs.txt
    cat << 'EOF' > /home/user/qemu_procs.txt
user 1001 /usr/bin/qemu-system-x86_64 -name web01 -m 8192 -smp 4 -daemonize
user 1002 /usr/bin/qemu-system-x86_64 -name db01 -m 32768 -smp 16 -daemonize
user 1003 /usr/bin/qemu-system-x86_64 -name cache01 -m 16384 -smp 8 -daemonize
user 1004 /usr/bin/qemu-system-x86_64 -name app01 -m 16384 -smp 8 -daemonize
user 1005 /usr/bin/qemu-system-x86_64 -name legacy01 -m 4096 -smp 2 -daemonize
EOF

    # Git setup
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init --bare /home/user/infra.git
    git clone /home/user/infra.git /home/user/infra_workspace

    echo "[]" > /home/user/infra_workspace/vms.json
    cd /home/user/infra_workspace
    git add vms.json
    git commit -m "init"
    git push origin master

    chmod -R 777 /home/user
