#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_metrics.csv
timestamp,cpu_percent,mem_percent,network_in_kb,network_out_kb,error_flag
1620000000,45.2,60.1,2048,1024,0
1620000060,95.5,85.2,10240,5120,0
1620000120,20.1,40.0,512,256,0
1620000180,,50.0,1024,1024,0
1620000240,88.0,90.5,8192,4096,1
1620000300,75.0,80.0,4096,2048,0
1620000360,99.9,95.0,20480,10240,0
1620000420,10.0,20.0,128,,0
1620000480,50.0,50.0,1024,1024,0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
