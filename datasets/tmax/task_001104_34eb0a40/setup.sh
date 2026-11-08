#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Generate the raw_sensors.csv file
    python3 -c "
import csv
import os

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/raw_sensors.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'S1', 'S2', 'S3', 'S4', 'S5'])
    for t in range(1, 501):
        row = [t]
        for i in range(1, 6):
            val = t**2 + i
            # Create isolated missing values
            if (t==10 and i==2) or (t==45 and i==4) or (t==100 and i==1) or (t==350 and i==5):
                row.append('')
            else:
                row.append(val)
        writer.writerow(row)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
