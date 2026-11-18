#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/storage

    cat << 'EOF' > /home/user/storage/raw_app.log
[2023-10-24 08:12:01] INFO System startup initiated.
[2023-10-24 08:12:05] WARN Storage latency detected on /dev/sda1.
[2023-10-24 08:15:30] ERROR Fatal kernel panic simulated.
===BEGIN DUMP===
5468697320697320612073656372
65742062696e617279207061796c
6f61642068696464656e20696e20
746865206c6f67732e0a
===END DUMP===
[2023-10-24 08:16:00] INFO Rebooting system...
[2023-10-24 08:16:15] INFO System back online.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
