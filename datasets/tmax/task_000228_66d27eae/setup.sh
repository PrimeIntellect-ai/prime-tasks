#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/conf
    mkdir -p /home/user/scripts
    mkdir -p /home/user/run/sockets

    cat << 'EOF' > /home/user/conf/fstab
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
user_data /home/user/run/sockets tmpfs rw,nodev 0 0
tmpfs /tmp tmpfs rw 0 0
EOF

    chown -R user:user /home/user/conf /home/user/scripts /home/user/run
    chmod -R 777 /home/user
