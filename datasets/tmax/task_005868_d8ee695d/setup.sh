#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensors.csv
machine_id,temp,vibration
1,45.2,0.12
2,50.1,0.15
3,42.5,0.08
4,60.0,0.40
5,48.2,0.10
6,55.5,0.25
7,44.0,0.11
8,62.1,0.50
9,47.8,0.09
10,59.2,0.35
EOF

    cat << 'EOF' > /home/user/data/maintenance.csv
machine_id,days_since_last_service
1,10
3,5
4,120
6,45
8,200
9,15
EOF

    cat << 'EOF' > /home/user/data/labels.csv
machine_id,failed
1,0
2,0
3,0
4,1
5,0
6,0
7,0
8,1
9,0
10,1
EOF

    chmod -R 777 /home/user
