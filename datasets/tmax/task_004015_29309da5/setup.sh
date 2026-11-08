#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile

os.makedirs('/home/user/remote_data', exist_ok=True)
os.makedirs('/home/user/workspace', exist_ok=True)

csv_content = """timestamp,sensor_alpha,sensor_beta,sensor_gamma,remarks
2023-10-01 10:00:00,10.5,20.1,30.2,Routine check
10/01/2023 10:05:00,10.6,,30.5,"Notice:
Intermittent signal
on beta"
2023-10-01 10:00:00,10.5,20.1,30.2,Routine check
2023-10-01 10:10:00,10.8,20.5,30.8,All clear
10/01/2023 10:15,11.0,20.7,,"Gamma offline
restarting"
"""

csv_path = '/home/user/remote_data/raw_sensors.csv'
with open(csv_path, 'w', encoding='utf-8') as f:
    f.write(csv_content)

tar_path = '/home/user/remote_data/sensor_dump.tar.gz'
with tarfile.open(tar_path, "w:gz") as tar:
    tar.add(csv_path, arcname='raw_sensors.csv')

os.remove(csv_path)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
