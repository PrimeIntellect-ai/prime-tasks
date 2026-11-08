#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
timestamp,sensor_id,value
1001,S1,10.0
1002,S2,20.0
1003,S1,12.0
1004,S2,22.0
1001,S1,10.0
1005,S1,11.0
1006,S2,21.0
1007,S1,50.0
1008,S2,23.0
1009,S1,11.0
1003,S1,12.0
1010,S2,80.0
EOF

    chmod -R 777 /home/user
