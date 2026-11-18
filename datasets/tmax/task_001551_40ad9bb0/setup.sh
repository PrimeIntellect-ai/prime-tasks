#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    # Generate raw_data.csv
    cat << 'EOF' > /home/user/data/raw_data.csv
id,a,b,c
1,1.0,2.0,3.0
2,0.5,1.5,2.0
3,2.0,1.0,4.0
4,1.5,2.5,5.0
5,0.8,1.2,1.8
EOF

    # Generate ref_states.csv
    cat << 'EOF' > /home/user/data/ref_states.csv
id,ref_x
1,0.55
2,0.60
3,0.70
4,0.85
5,0.45
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
