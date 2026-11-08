#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/app.log
[2023-10-01 10:00:00] INFO: msg1
[2023-10-01 10:00:05] INFO: msg22
[2023-10-01 10:00:10] INFO: msg333
[2023-10-01 10:00:15] INFO: msg4444
[2023-10-01 10:00:20] INFO: msg55555
[2023-10-01 10:00:25] INFO: This is a very long message
that spans multiple lines
and should definitely trigger an anomaly!
[2023-10-01 10:00:30] INFO: msg7777777
[2023-10-01 10:00:35] ERROR: Short
[2023-10-01 10:00:40] WARN: msg88888888
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
