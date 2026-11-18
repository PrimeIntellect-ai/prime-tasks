#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_logs.csv
server_id,cpu_usage,ram_usage,disk_io
SRV-001,45.0,60.0,120
SRV-002,NaN,80.0,200
SRV-003,150.0,90.0,300
SRV-004,10.0,20.0,50
SRV-999,50.0,55.0,100
EOF

    cat << 'EOF' > /home/user/server_info.csv
server_id,os,prior_failure_prob
SRV-001,linux,0.01
SRV-002,linux,0.05
SRV-003,windows,0.10
SRV-004,linux,0.02
SRV-999,linux,0.01
EOF

    chmod -R 777 /home/user
