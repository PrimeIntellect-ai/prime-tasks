#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,value
1,sensor_A,10.0
2,sensor_A,12.0
3,sensor_A,14.0
4,sensor_A,13.0
5,sensor_A,15.0
1,sensor_B,100.0
2,sensor_B,105.0
3,sensor_B,102.0
4,sensor_B,110.0
5,sensor_B,108.0
1,sensor_C,50.0
2,sensor_C,50.0
3,sensor_C,50.0
4,sensor_C,50.0
5,sensor_C,50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
