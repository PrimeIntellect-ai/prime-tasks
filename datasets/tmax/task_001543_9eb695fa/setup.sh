#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/net_data

    cat << 'EOF' > /home/user/fstab.mock
UUID=ROOT-FS / ext4 defaults 1 1
UUID=OTHER-FS /mnt/other ext4 defaults 0 2
UUID=NET-CONFIG-FS /home/user/net_data ext4 defaults,user 0 0
UUID=SWAP none swap sw 0 0
EOF

    cat << 'EOF' > /home/user/net_data/config.ini
[Daemon]
ListenPort=0
LogLevel=DEBUG
EnableCache=true
EOF

    cat << 'EOF' > /home/user/iptables.dump
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -i eth0 -p tcp -m tcp --dport 443 -j REDIRECT --to-ports 8443
-A PREROUTING -i eth0 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 8088
-A PREROUTING -i eth0 -p tcp -m tcp --dport 8080 -j REDIRECT --to-ports 8089
COMMIT
EOF

    chmod -R 777 /home/user
