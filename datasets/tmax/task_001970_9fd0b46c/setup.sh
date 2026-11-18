#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pytz

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/output

    # Create stream_alpha.csv
    cat << 'EOF' > /home/user/data/stream_alpha.csv
timestamp,device_id,sensor_value,error_code
2023/10/01 10:00:00,DEV_A,45.23,0
2023/10/01 10:05:00,DEV_A,45.21,0
2023/10/01 10:10:00,DEV_B,-60.0,0
2023/10/01 10:15:00,DEV_C,100.0,1
2023/10/01 11:00:00,DEV_D,149.99,0
EOF

    # Create stream_beta.csv
    cat << 'EOF' > /home/user/data/stream_beta.csv
ts,dev,val,err
1696172400,DEV_A,45.25,0
1696176000,DEV_E,0.0,0
1696176060,DEV_E,0.04,0
1696180000,DEV_F,200.0,0
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
