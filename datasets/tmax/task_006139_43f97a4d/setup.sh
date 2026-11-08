#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,value
1600000000,10
1600000060,12
1600000180,15
1600000300,14
1600000420,18
1600000540,20
1600000600,22
1600000780,25
1600000900,21
1600001080,19
1600001200,16
1600001380,17
1600001500,20
1600001680,24
1600001800,26
EOF

    chmod -R 777 /home/user
