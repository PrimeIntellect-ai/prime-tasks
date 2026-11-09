#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app_data/logs
    mkdir -p /home/user/app_data/cache

    head -c 12450 /dev/urandom > /home/user/app_data/logs/syslog.log
    head -c 8192 /dev/urandom > /home/user/app_data/cache/data.bin
    head -c 42 /dev/urandom > /home/user/app_data/config.ini

    cat << 'EOF' > /home/user/mock_routes.txt
10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.5 
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown 
default via 10.0.0.254 dev eth0 proto dhcp src 10.0.0.5 metric 100 
EOF

    cat << 'EOF' > /home/user/config.json
{
  "locale": "en_US.UTF-8",
  "timezone": "Pacific/Auckland"
}
EOF

    cat << 'EOF' > /home/user/mock_etc_timezone
Pacific/Auckland
EOF

    cat << 'EOF' > /home/user/mock_ssh_config
Host bastion-host
    HostName bastion.example.com
    User admin
    IdentityFile ~/.ssh/id_rsa

Host web-prod-01
    HostName 10.0.1.10
    User deploy
    PubkeyAuthentication   No

Host db-backup
    HostName 10.0.2.50
    User backup
    PubkeyAuthentication no
    Port 2222

Host monitoring-node
    HostName 10.0.3.5
    User monitor
    PubkeyAuthentication yes
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
