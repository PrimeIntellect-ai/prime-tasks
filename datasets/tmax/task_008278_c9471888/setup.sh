#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install --no-cache-dir pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_sensors.txt
[INFO] MSG_ID=101 : F1=0.123456789 | F2=1.987654321 | F3=3.333333333 | F4=4.444444444
[INFO] MSG_ID=102 : F1=10000.12345 | F2=20000.54321 | F3=30000.11111 | F4=40000.99999
[INFO] MSG_ID=103 : F1=-0.00000012 | F2=0.00000034 | F3=-0.00000056 | F4=0.00000078
[INFO] MSG_ID=104 : F1=3.141592653 | F2=2.718281828 | F3=1.618033988 | F4=1.414213562
[INFO] MSG_ID=105 : F1=123.4567890 | F2=-123.456789 | F3=987.6543210 | F4=-987.654321
EOF

    chmod -R 777 /home/user
