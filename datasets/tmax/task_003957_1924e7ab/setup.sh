#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/raw_data /home/user/output /home/user/archive

    # Create input CSV file
    cat << 'EOF' > /home/user/raw_data/user_features.csv
user_id,f1,f2,f3
U001,10.0,5.0,1.0
U002,9.5,4.8,1.1
U003,2.0,8.0,5.0
U004,10.5,5.5,0.9
U005,8.0,4.0,0.8
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
