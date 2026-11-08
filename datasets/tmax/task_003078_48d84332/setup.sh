#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.csv
1700000000,Sensor\u0020A,10.00
1700000015,Sensor\u0020A,12.00
1700000030,Loc\u00e1tionB,15.50
1700000059,Loc\u00e1tionB,16.00
1700000150,T\u00e9st\u2713,20.00
1700000160,Sensor A,99.99
1700000200,New\u0020Data,25.00
EOF

    chmod -R 777 /home/user
