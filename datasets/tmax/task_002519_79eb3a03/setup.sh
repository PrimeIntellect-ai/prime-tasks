#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_A,sensor_B
t1,10.0,20.0
t2,12.0,25.0
t3,11.1,error
t4,9.0,19.0
t5,15.0,31.0
t_bad,10.0
t6,14.0,27.0
t7,16.0,33.0
t8,bad,bad
t9,8.0,16.0
t10,20.0,40.0,extra
t11,11.0,22.0
EOF

    chmod -R 777 /home/user
