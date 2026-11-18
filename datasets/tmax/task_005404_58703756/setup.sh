#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
timestamp,cpu_usage,memory_usage_mb,disk_io_errors
2023-01-01,45.5,8000,0
2023-01-02,NULL,8500,1
2023-01-03,150.0,9000,0
2023-01-04,55.2,8200,0
2023-01-05,60.1,7900,2
2023-01-06,42.0,8100,0
2023-01-07,-5.0,8000,0
2023-01-08,48.9,8300,0
2023-01-09,,8400,1
2023-01-10,50.3,8000,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
