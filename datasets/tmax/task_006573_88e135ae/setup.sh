#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.txt
S01|1700000000|20.5
S01|1700000000|22.0
S01|1700000050|21.0
S01|1700001000|invalid
S01|1700007200|24.0
S01|1700007205|24.2
S01|1700010800|19.5
S02|1700003600|10.0
S02|1700003700|12.0
S02|1700003600|10.5
S02|17000000000|15.0
S02|1700014400|9.0
S02|999999999|8.0
S03|1700000000|14.0
S03|1700000000|14.0
S03|1700003600|15.0
S01|1700007200|-24.0
EOF

    chmod -R 777 /home/user
    chmod 644 /home/user/sensor_data.txt
