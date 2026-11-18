#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client openssh-server
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh

    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/.ssh/config
Host router-01
    HostName 127.0.0.1
    User user
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
EOF

    echo "hostname ROUTER-01" > /home/user/router_config.txt
    echo "interface eth0" >> /home/user/router_config.txt
    echo " ip address 10.0.0.1 255.255.255.0" >> /home/user/router_config.txt

    cat << 'EOF' > /home/user/network_fstab
# device mountpoint fstype options dump fsck
/dev/sda1 / ext4 defaults 1 1
//storage-node/router-backups /home/user/mnt/backups cifs defaults,uid=1000,gid=1000 0 0
tmpfs /tmp tmpfs defaults 0 0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user

    # Fix SSH permissions to match required secure values (and intentionally broken ones)
    chmod 700 /home/user/.ssh
    chmod 644 /home/user/.ssh/id_rsa
    chmod 644 /home/user/.ssh/id_rsa.pub
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/config
