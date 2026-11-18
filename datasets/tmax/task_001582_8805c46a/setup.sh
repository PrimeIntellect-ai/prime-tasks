#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_A.log
[2023-10-01 10:00:00 UTC] POS: lat=10.5, lon=-5.2
[2023-10-01 10:05:00 UTC] POS: lat=12.1, lon=-4.8
[2023-10-01 10:10:00 UTC] POS: lat=11.0, lon=-6.0
[2023-10-01 10:15:00 UTC] POS: lat=9.5, lon=-7.1
EOF

    cat << 'EOF' > /home/user/sensor_B.csv
epoch,temp
1696154390,22.1
1696154402,22.5
1696154705,23.1
1696154720,23.5
1696154980,21.0
1696155001,21.8
1696155305,20.5
1696155350,19.8
EOF

    chmod -R 777 /home/user
