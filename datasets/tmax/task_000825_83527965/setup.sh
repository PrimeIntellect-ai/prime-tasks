#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.csv
timestamp,cpu_usage,memory_usage,response_time
2023-10-01T10:00:00,45.2,1000,120
2023-10-01T10:01:00,105.0,2000,150
2023-10-01T10:02:00,40.1,,110
2023-10-01T10:03:00,-5.0,2000,130
2023-10-01T10:04:00,60.5,3000,140
2023-10-01T10:05:00,,2000,160
2023-10-01T10:06:00,55.0,4000,180
EOF

    chmod -R 777 /home/user
