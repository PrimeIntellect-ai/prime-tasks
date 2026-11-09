#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc gzip
    pip3 install pytest

    mkdir -p /home/user/sensor_data
    cd /home/user/sensor_data

    cat << 'EOF' > alpha.csv
timestamp,sensor_id,value
1620000000,alpha_1,42.5
1620000001,alpha_1,42.7
EOF

    cat << 'EOF' > beta.csv
timestamp,sensor_id,value
1620000000,beta_1,-12.3
1620000002,beta_1,-11.9
1620000004,beta_1,-12.0
EOF

    cat << 'EOF' > gamma.csv
timestamp,sensor_id,value
1620000000,gamma_2,0.0
EOF

    gzip alpha.csv
    gzip beta.csv
    gzip gamma.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
