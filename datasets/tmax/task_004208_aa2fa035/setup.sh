#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metrics.csv
timestamp,cpu,memory,disk
2023-10-01T10:01:15Z,45.5,1024,50
2023-10-01T10:04:10Z,50.0,1048,60
2023-10-01T10:11:00Z,80.0,2048,120
2023-10-01T10:16:30Z,40.0,512,30
EOF

    cat << 'EOF' > /home/user/logs.csv
timestamp,message
2023-10-01 10:02:00,"Connection timeout occurred!"
2023-10-01 10:04:30,"Normal operation."
2023-10-01 10:06:15,"ERROR 500: Database error."
2023-10-01 10:12:00,"Timeout on endpoint A."
2023-10-01 10:18:00,"System error, timeout reported."
EOF

    chmod -R 777 /home/user
