#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas jinja2

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
timestamp,temp_A,log_A,temp_B,log_B
2023-11-01 10:00:00,20.5,Valve opened.,22.1,System normal
2023-11-01 10:05:00,21.0,,22.5,
2023-11-01 10:30:00,23.5,Valve opened heavily!,23.0,Warning: High pressure
2023-11-01 11:00:00,21.0,System cool down.,21.5,Warning - high pressures!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
