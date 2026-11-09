#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs

    cat << 'EOF' > /home/user/raw_configs/batch_1.csv
Raw_Time,web01_timeout,web01_workers,db01_timeout,db01_workers
2023-05-10 08:15:30,30,4,60,8
05/10/2023 08:45:00,30,5,60,8
2023-05-10 09:05:00,45,5,,8
EOF

    cat << 'EOF' > /home/user/raw_configs/batch_2.csv
Raw_Time,web01_timeout,web01_workers,db01_timeout,db01_workers
2023-05-11 14:20:00,45,8,120,16
05/11/2023 14:55:00,60,8,120,16
2023-05-11 15:00:00,60,8,120,32
EOF

    chown -R user:user /home/user/raw_configs
    chmod -R 777 /home/user
