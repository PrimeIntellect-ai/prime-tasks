#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/incoming/', exist_ok=True)
with open('/home/user/incoming/dataset_a.csv', 'w', encoding='utf-16le') as f:
    f.write('ProjectID: OMEGA-77\nMeasurement,Value\nTemp,98.6\nPress,1.01\n')
with open('/home/user/incoming/dataset_b.dat', 'w', encoding='iso-8859-1') as f:
    f.write('ProjectID: DELTA-04\nMeasurement,Value\nTemp,101.2\nPress,0.99\n')
"

    chown -R user:user /home/user
    chmod -R 777 /home/user
