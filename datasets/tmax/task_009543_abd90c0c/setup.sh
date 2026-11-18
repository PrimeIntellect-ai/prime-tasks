#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/disk_usage.txt
Filesystem     1M-blocks  Used Available Use% Mounted on
/dev/sda1          50000 45000      5000  90% /
tmpfs               1000    10       990   1% /tmp
/dev/sdb1         100000 85000     15000  85% /data
/dev/sdc1          20000 10000     10000  50% /backup
/dev/sdd1          30000 24000      6000  80% /var
EOF

    cat << 'EOF' > /home/user/routes.txt
default via 192.168.1.1 dev eth0 proto dhcp metric 100
10.0.0.0/8 dev eth1 proto kernel scope link src 10.0.0.2
192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.5 metric 100
EOF

    chmod -R 777 /home/user
