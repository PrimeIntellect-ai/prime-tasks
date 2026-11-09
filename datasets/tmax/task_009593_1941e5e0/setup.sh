#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensors.csv
id,sensor1,sensor2,sensor3
1,0.2,0.8,1.5
2,0.9,0.1,2.2
3,invalid,0.5,1.0
4,0.6,0.6,0.6
5,0.1,0.9,1.1
6,0.8,0.2,2.0
7,0.4,0.5,1.5
EOF

    cat << 'EOF' > /home/user/labels.csv
id,label
1,0
2,1
4,1
5,0
6,1
7,2
8,1
EOF

    chmod -R 777 /home/user
