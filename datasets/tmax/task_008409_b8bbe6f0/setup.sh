#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/raw_logs.txt
[2023-10-01T10:00:00Z] node_ip=10.0.0.1 type=metric key=cpu val=500
[2023-10-01T10:00:00Z] node_ip=10.0.0.1 type=metric key=mem val=8000
[2023-10-01T10:00:00Z] node_ip=10.0.0.2 type=metric key=cpu val=200
[2023-10-01T10:00:00Z] node_ip=10.0.0.2 type=metric key=mem val=4000
[2023-10-01T10:05:00Z] node_ip=10.0.0.1 type=metric key=cpu val=600
[2023-10-01T10:05:00Z] node_ip=10.0.0.1 type=metric key=mem val=8500
[2023-10-01T10:05:00Z] node_ip=10.0.0.1 type=metric key=cpu val=600
[2023-10-01T10:05:00Z] node_ip=10.0.0.1 type=metric key=mem val=8500
[2023-10-01T10:05:00Z] node_ip=10.0.0.3 type=metric key=cpu val=900
[2023-10-01T10:05:00Z] node_ip=10.0.0.3 type=metric key=mem val=16000
EOF

    cat << 'EOF' > /home/user/data/capacities.csv
ip_address,max_cpu,max_mem
10.0.0.1,1000,16000
10.0.0.2,2000,32000
10.0.0.3,1000,16000
EOF

    cat << 'EOF' > /home/user/data/locations.csv
ip_address,datacenter
10.0.0.1,us-east-1
10.0.0.2,eu-west-1
10.0.0.3,ap-south-1
EOF

    chmod -R 777 /home/user
