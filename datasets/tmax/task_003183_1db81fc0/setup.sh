#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
1000,2.0,3.0,50.0
1005,4.0,5.0,60.0
1012,6.0,8.0,40.0
1021,5.0,12.0,30.0
1035,8.0,15.0,20.0
1040,15.0,20.0,70.0
1045,-3.0,-4.0,65.0
1059,20.0,21.0,80.0
EOF

    chmod -R 777 /home/user
