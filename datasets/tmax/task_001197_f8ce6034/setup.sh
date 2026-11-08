#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_events.log
[2023-11-01 10:05:12] SVC:auth DEDUPE:h001 METRICS:cpu=12,mem=512
[2023-11-01 10:10:45] SVC:db DEDUPE:h002 METRICS:cpu=80,mem=2048,disk=100
[2023-11-01 10:14:59] SVC:auth DEDUPE:h001 METRICS:cpu=12,mem=512
[2023-11-01 10:16:02] SVC:auth DEDUPE:h003 METRICS:cpu=20,mem=600
[2023-11-01 10:18:00] SVC:db DEDUPE:h004 METRICS:cpu=85,disk=120
[2023-11-01 10:25:00] SVC:db DEDUPE:h005 METRICS:cpu=82,mem=2100,disk=110
[2023-11-01 10:31:00] SVC:auth DEDUPE:h006 METRICS:cpu=15,mem=550
EOF

    chown user:user /home/user/system_events.log
    chmod -R 777 /home/user
