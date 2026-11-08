#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev tar
    pip3 install pytest

    mkdir -p /home/user/sys_root/etc/app1
    mkdir -p /home/user/sys_root/etc/app2
    mkdir -p /home/user/sys_root/var/lib/app3
    mkdir -p /home/user/sys_root/opt/ignored

    cat << 'EOF' > /home/user/sys_root/etc/app1/net.conf
[network]
server_ip=192.168.1.100
port=8080
EOF

    cat << 'EOF' > /home/user/sys_root/etc/app2/settings.conf
debug=true
server_ip=10.0.0.5
timeout=30
EOF

    cat << 'EOF' > /home/user/sys_root/var/lib/app3/data.conf
path=/var/data
server_ip=127.0.0.1
EOF

    cat << 'EOF' > /home/user/sys_root/opt/ignored/skip.conf
server_ip=0.0.0.0
EOF

    cat << 'EOF' > /home/user/backup_targets.ini
[targets]
etc/app1
etc/app2
var/lib/app3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
