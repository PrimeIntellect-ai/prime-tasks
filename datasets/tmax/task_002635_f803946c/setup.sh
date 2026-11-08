#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tzdata
    pip3 install pytest

    mkdir -p /home/user/sys_config/

    cat << 'EOF' > /home/user/sys_config/fstab
# /etc/fstab: static file system information.
UUID=8a9b3c4d / ext4 errors=remount-ro 0 1
UUID=11223344 /boot vfat umask=0077 0 1
UUID=55667788 /var/log ext4 defaults 0 2
UUID=99aabbcc /mnt/backup xfs defaults 0 2
EOF

    cat << 'EOF' > /home/user/sys_config/routes
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         10.0.2.1        0.0.0.0         UG    100    0        0 eth0
10.0.2.0        0.0.0.0         255.255.255.0   U     100    0        0 eth0
192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
