#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
1.2,3.4,NaN,7.8,9.1
1.5,3.6,5.1,7.5,9.3
100.0,3.1,4.8,NaN,9.0
1.1,150.0,4.9,7.6,9.2
1.3,3.3,5.0,7.7,-50.0
1.4,3.5,4.7,7.9,9.4
1.2,3.2,5.2,7.4,9.5
EOF

    chmod -R 777 /home/user
