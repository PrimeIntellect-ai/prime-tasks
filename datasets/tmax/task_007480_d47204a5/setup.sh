#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/etl_run_1.csv
2023-10-01T10:00:00Z,usr001, purchase ,100
2023-10-01T10:05:00Z,usr001, purchase ,100
2023-10-01T10:02:00Z,usr002, Login ,0
2023-10-01T10:15:00Z,usr001,purchase,1001
2023-10-01 10:20:00,usr003,purchase,50
2023-10-01T10:25:00Z,usr002,refund,20
2023-10-01T10:30:00Z,usr002,purchase,250
EOF

    cat << 'EOF' > /home/user/data/etl_run_2.csv
2023-10-01T10:35:00Z,usr001,purchase,150
2023-10-01T10:40:00Z,usr001,purchase,1600
2023-10-01T10:45:00Z,invalid_user,purchase,100
2023-10-01T10:50:00Z,usr004,purchase,-10
2023-10-01T10:05:00Z,usr001, purchase ,100
EOF

    cat << 'EOF' > /home/user/expected_cleaned.csv
2023-10-01T10:00:00Z,usr001,purchase,100
2023-10-01T10:02:00Z,usr002,login,0
2023-10-01T10:05:00Z,usr001,purchase,100
2023-10-01T10:25:00Z,usr002,refund,20
2023-10-01T10:35:00Z,usr001,purchase,150
EOF

    cat << 'EOF' > /home/user/expected_anomalies.csv
2023-10-01T10:15:00Z,usr001,purchase,1001
2023-10-01T10:30:00Z,usr002,purchase,250
2023-10-01T10:40:00Z,usr001,purchase,1600
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
