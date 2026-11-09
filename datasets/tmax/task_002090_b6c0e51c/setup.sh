#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,value
1000, s1 ,10.0
1000,s1,10.0
1001,S1,12.0
1002,S1,11.0
1002,S1,11.0
1003,s1,-5.0
1004,S1,30.0
1005,s2,50.0
1006,S2,bad
1007,S2,52.0
1008,S2,110.0
1005,S2,50.0
1009,S1,15.0
1010,S1,50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
