#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ git openssh-client openssh-server
    pip3 install pytest

    mkdir -p /home/user/uptime.git/hooks
    mkdir -p /home/user/workspace
    mkdir -p /home/user/reports_dir

    cat << 'EOF' > /home/user/fstab.mock
# /etc/fstab: static file system information.
proc /proc proc defaults 0 0
/dev/sda1 / ext4 errors=remount-ro 0 1
/dev/mapper/uptime_data /home/user/reports_dir ext4 defaults 0 2
tmpfs /tmp tmpfs defaults 0 0
EOF

    cat << 'EOF' > /home/user/workspace/heartbeat.log
1700000000 UP
1700000060 UP
1700000120 DOWN
1700000180 UP
1700000240 UP
1700000300 DOWN
1700000360 UP
1700000420 UP
1700000480 UP
1700000540 UP
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
