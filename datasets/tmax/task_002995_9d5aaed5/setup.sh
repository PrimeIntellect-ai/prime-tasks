#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,value
1000,S1,20.0
1001,S1,22.0
1002,S1,21.0
1003,S1,19.0
1004,S1,-60.0
1005,S1,23.0
1006,S1,46.0
1007,S2,10.0
1008,S1,47.0
1009,S1,48.0
1010,S1,46.5
1011,S1,47.2
1012,S1,12.0
1013,S2,11.0
1014,S2,10.5
1015,S2,11.2
1016,S2,10.8
1017,S2,40.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
