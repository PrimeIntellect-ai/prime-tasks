#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    mkdir -p /home/user/data/raw

    python3 -c "
import os
os.makedirs('/home/user/data/raw', exist_ok=True)
with open('/home/user/data/raw/day3.dat', 'wb') as f:
    f.write('Daily system logs and metrics.\nSystem healthy. Readout: [2023-10-03 10:00:00] -> 14.9 units. End of report.\n'.encode('utf-8'))
with open('/home/user/data/raw/day1.dat', 'wb') as f:
    f.write('Legacy system B metrics. Readout: [2023-10-01 10:00:00] -> 15.2 units.'.encode('utf-16le'))
with open('/home/user/data/raw/day2.dat', 'wb') as f:
    f.write('European server metrics (café). Readout: [2023-10-02 10:00:00] -> 16.8 units.'.encode('iso-8859-1'))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
