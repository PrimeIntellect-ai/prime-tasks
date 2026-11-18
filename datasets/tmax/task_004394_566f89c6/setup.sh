#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_config_metrics.csv
timestamp,server_id,config_size_bytes,changes_count
2023-10-01T08:00:00Z,srv-alpha,1000,1
2023-10-01T15:00:00Z,srv-alpha,1050,2
2023-10-01T09:00:00Z,srv-beta,500,1
2023-10-03T10:00:00Z,srv-alpha,1100,1
2023-10-04T10:00:00Z,srv-alpha,1100,0
2023-10-05T10:00:00Z,srv-alpha,2000,5
2023-10-06T10:00:00Z,srv-alpha,2050,1
2023-10-07T10:00:00Z,srv-alpha,2050,0
2023-10-08T10:00:00Z,srv-alpha,1000,3
2023-10-02T09:00:00Z,srv-beta,550,2
2023-10-05T09:00:00Z,srv-beta,550,0
2023-10-06T09:00:00Z,srv-beta,1500,4
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
