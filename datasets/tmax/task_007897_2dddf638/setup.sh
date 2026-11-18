#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/servers.csv
ServerID,OS,CPU_Load,Mem_Used_MB,Disk_IOPS
srv_001,Linux,45.5,8192,120
srv_002,Windows,,4096,800
srv_003,Linux,12.0,,50
srv_004,BSD,99.9,16384,1500
srv_005,Windows,85.5,8192,
EOF

    cat << 'EOF' > /home/user/model_spec.txt
MODEL_CONFIG_v1.0
BIAS: -15.5
ALERT_THRESHOLD: 80.0

WEIGHTS_CONTINUOUS:
CPU_Load: 0.8
Mem_Used_MB: 0.002
Disk_IOPS: 0.05

WEIGHTS_CATEGORICAL_OS:
Linux: 5.0
Windows: 12.5
BSD: 2.0
EOF

    chmod -R 777 /home/user
