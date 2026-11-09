#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_data.csv
sim_id,v0,target_v10
1,0.0,30.0
2,10.0,15.0
3,0.0,50.0
4,5.0,22.0
EOF

    chmod -R 777 /home/user
