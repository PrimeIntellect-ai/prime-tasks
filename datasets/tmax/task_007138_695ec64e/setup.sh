#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os

mock_log = """[BEGIN]   
Timestamp: 2023-05-12 08:00:00
Station: Alpha
Temp: 22.5
FaultCode: 0
[END]
  [BEGIN]
Timestamp: 2023-05-12 08:15:00
Station: Beta
Temp: -99.9
FaultCode: 1
 [END]  
[BEGIN]
Timestamp: 2023-05-12 08:30:00
Station: Alpha
Temp: 23.1
FaultCode: 0
[END]
"""

mock_log_crlf = mock_log.replace('\n', '\r\n')

with open('/home/user/raw_sensor.log', 'wb') as f:
    f.write(mock_log_crlf.encode('utf-16le'))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
