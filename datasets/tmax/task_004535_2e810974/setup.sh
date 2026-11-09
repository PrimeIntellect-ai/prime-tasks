#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/raw_metrics.csv
timestamp,host,cpu_load,memory_usage,disk_io,notes
2023/10/01,srv1,45,80,120,Normal operation
10-02-2023,srv2,50,85,130,"Disk replaced
All good"
2023/10/03,srv1,60,90,140,High load
10-04-2023,srv3,10,20,30,"Routine
Maintenance
Logged"
2023/10/05,srv2,55,88,125,Updated OS
EOF

    chmod -R 777 /home/user
