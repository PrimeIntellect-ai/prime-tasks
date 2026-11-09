#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
run_id,timestamp,sensor1,sensor2
1,1000,10.0,20.0
1,1001,12.0,22.0
2,1001,13.0,21.0
1,1002,11.0,25.0
1,1003,30.0,20.0
3,1003,32.0,19.0
1,1004,15.0,20.0
EOF

    chmod -R 777 /home/user
