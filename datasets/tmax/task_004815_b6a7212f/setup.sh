#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.log
2023-10-01 09:59:00 - Boot sequence initiated
2023-10-01 10:01:15 - System check: metric=temperature val=45.2
2023-10-01 10:03:00 - Disk scrub started
2023-10-01 10:04:45 - System check: metric=memory val=1024.0
2023-10-01 10:06:10 - System check: metric=cpu val=60.0
2023-10-01 10:09:05 - System check: metric=cpu val=62.0
2023-10-01 10:11:05 - System check: metric=temperature val=47.5
2023-10-01 10:14:20 - System check: metric=memory val=2048.0
2023-10-01 10:18:00 - System check: metric=cpu val=40.5
2023-10-01 10:21:00 - System check: metric=cpu val=99.9
EOF

    chmod -R 777 /home/user
