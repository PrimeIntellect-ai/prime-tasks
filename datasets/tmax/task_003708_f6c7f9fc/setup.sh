#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_measurements.csv
temp,pressure,humidity,vibration,failure_score
20.0,1.0,50.0,0.5,10.0
22.0,1.1,52.0,0.4,11.2
19.5,0.9,48.0,0.6,9.8
21.0,1.05,51.0,0.55,10.5
23.0,1.2,55.0,0.3,12.0
25.0,1.3,58.0,0.2,13.5
18.0,0.85,45.0,0.7,9.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
