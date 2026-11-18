#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
os.makedirs('/home/user', exist_ok=True)
with open('/home/user/raw_sensor_data.csv', 'wb') as f:
    f.write(b'timestamp,sensor_id,temperature,metadata\r\n')
    f.write(b'2023-10-01T10:00:00,S1,22.5,Normal operation\r\n')
    f.write(b'2023-10-01T09:00:00,S1,21.0,"Restarted\nwith error \x80"\r\n')
    f.write(b'2023-10-01T11:00:00,S1,19.0,Low temp\r\n')
    f.write(b'2023-10-01T12:00:00,S1,25.0,"High temp\nagain"\r\n')
    f.write(b'2023-10-01T08:00:00,S2,24.1,"Initial\r\nstartup"\r\n')
    f.write(b'2023-10-01T08:30:00,S2,,Sensor offline\r\n')
    f.write(b'2023-10-01T09:15:00,S2,20.5,"Back online\nall good"\r\n')
    f.write(b'2023-10-01T10:15:00,S2,26.0,Overheating \xb0C\r\n')
    f.write(b'2023-10-01T07:00:00,S1,28.0,Early bird\r\n')
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
