#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy

    mkdir -p /home/user/raw_data
    cat << 'EOF' > /home/user/raw_data/part1.csv
timestamp,feature_alpha
5,4.0
1,0.0
3,2.0
2,1.0
4,3.0
EOF

    cat << 'EOF' > /home/user/raw_data/part2.csv
timestamp,feature_beta
2,3.03265
5,0.67668
4,1.11565
3,1.83940
1,5.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
