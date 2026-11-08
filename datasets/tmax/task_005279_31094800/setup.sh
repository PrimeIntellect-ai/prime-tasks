#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import csv

with open('/home/user/raw_data.csv', 'w') as f:
    f.write('1000,S1,15.0,50.0,ok\n')
    f.write('1030,S1,16.5,51.0,ok\n')
    f.write('1050,S1,17.0,52.0,"bad\nnewline"\n')
    f.write('1070,S1,18.0,53.0,ok\n')
    f.write('1100,S1,19.5,54.0,ok\n')
    f.write('1180,S1,22.0,55.0,ok\n')
    f.write('1240,S1,25.5,56.0,ok\n')
    f.write('1300,S1,28.0,57.0,ok\n')
    f.write('1360,S1,31.0,58.0,ok\n')
    f.write('1390,S1,32.0,59.0,dropped\nnewline\n')
    f.write('1420,S1,33.5,60.0,ok\n')
    f.write('1480,S1,35.0,61.0,ok\n')
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
