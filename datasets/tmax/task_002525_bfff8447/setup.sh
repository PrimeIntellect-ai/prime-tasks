#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sensor_A.csv
1622548810,10.0
1622548825,12.0
1622548880,15.5
1622548900,16.5
1622549000,20.0
EOF

    cat << 'EOF' > /home/user/data/sensor_B.csv
1622548815,100.0
1622548930,110.0
1622548940,120.0
EOF

    cat << 'EOF' > /home/user/data/sensor_C.csv
1622548850,5.5
1622548870,6.5
1622549005,8.0
1622549010,9.0
EOF

    chown -R user:user /home/user/data /home/user/output
    chmod -R 777 /home/user
