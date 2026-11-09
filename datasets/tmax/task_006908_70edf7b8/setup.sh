#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,sensor_id,temperature
1600000000,S1,22.5
1600001800,S1,23.5
1600003600,S1,155.0
1600007200,S1,24.0
1600014400,S1,25.0
1600018000,S1,
1600021600,S1,invalid
1600000000,S2,-60.0
1600003600,S2,10.0
1600010800,S2,12.0
EOF

    chmod -R 777 /home/user
