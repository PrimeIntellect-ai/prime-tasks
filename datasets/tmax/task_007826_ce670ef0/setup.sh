#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/router_configs
    mkdir -p /home/user/mnt/remote_backups

    echo "hostname router01" > /home/user/router_configs/r1.cfg
    echo -e "hostname router02\ninterface eth0\nip address 10.0.0.1 255.255.255.0" > /home/user/router_configs/r2.cfg
    echo "ignore this file" > /home/user/router_configs/readme.txt

    cat << 'EOF' > /home/user/network_fstab
# /etc/fstab: static file system information.
UUID=1234-5678 / ext4 defaults 1 1
//10.0.0.5/shared /home/user/mnt/shared cifs ro 0 0
//192.168.1.100/net_backups /home/user/mnt/remote_backups cifs rw,credentials=/etc/smbcredentials 0 0
tmpfs /run tmpfs rw,nosuid,nodev 0 0
EOF

    chmod -R 777 /home/user
