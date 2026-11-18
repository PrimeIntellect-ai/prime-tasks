#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
timestamp,sensor_id,status,reading
1620000000,T-800,VALID,10.5
1620000001,T-800,ERROR,99.9
1620000002,T-801,VALID,12.1
1620000003,T-800,VALID,11.2
1620000004,T-800,VALID,10.8
1620000005,T-800,NOISE,15.0
1620000006,T-800,VALID,9.7
1620000007,T-802,VALID,100.5
1620000008,T-800,VALID,10.1
1620000009,T-800,VALID,11.5
EOF

    chmod -R 777 /home/user
