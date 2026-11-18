#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc file
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import codecs

data1 = "SENS_A,1.0,2.0,3.0\nSENS_C,10.0,10.0\nSENS_B,4.0,5.0,6.0\n"
data2 = "SENS_D,2.0,2.0\nSENS_E,0.0\nSENS_F,10.0,10.0\n"

with open("/home/user/data1.txt", "w", encoding="utf-16") as f:
    f.write(data1)

with open("/home/user/data2.txt", "w", encoding="utf-16") as f:
    f.write(data2)
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
