#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/weights.txt
w_temp=0.45
w_press=1.15
bias=-8.50
EOF

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,temperature,pressure
1600000000,1,25.5,101.3
1600000010,2,,100.5
1600000020,3,-10.0,99.8
1600000030,4,22.0,101.0
1600000040,1,200.0,102.1
1600000050,2,24.0,
1600000060,2,22.0,100.0
1600000070,3,NaN,98.5
1600000080,A,25.0,100.0
1600000090,1,-60.0,101.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
