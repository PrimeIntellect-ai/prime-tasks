#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_configs.csv
Timestamp,ServerID,CPUCores,MemGigabytes,MaxConnections
2023-11-01T08:15:30,srv-01,8,64,1500
2023-11-01T08:25:00,srv-01,8,64,1600
2023-11-01T08:10:00,srv-02,16,128,3000
2023-11-01T08:45:00,srv-02,16,128,invalid
2023-11-01T09:05:00,srv-01,16,64,2000
2023-11-01T09:15:00,srv-01,-4,64,2000
2023-11-01T09:35:00,srv-01,16,128,2500
2023-11-01T09:01:00,srv-03,4,32,500
2023-11-01T09:59:00,srv-03,4,32,500
2023-11-01T10:00:00,srv-01,16,128,2500
EOF

    chmod -R 777 /home/user
