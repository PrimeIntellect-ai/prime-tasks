#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,value
1620000000,S1,10000000.1
1620000001,S1,10000000.2
1620000002,S2,ERR
1620000003,S1,10000000.3
1620000004,S2,50000000.5
1620000005,S3,NaN
1620000006,S2,50000000.5
1620000007,S1,10000000.4
1620000008,S2,50000000.6
1620000009,S4,
1620000010,S2,50000000.5
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
