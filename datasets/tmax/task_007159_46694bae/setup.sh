#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

data = """id,timestamp,log_message,temperature
1,2023-10-01T10:00:00,User constr@example.com connected,20.0
2,2023-10-01T10:01:00,Café machine active admin@test.org,,
3,2023-10-01T10:02:00,Normal operation,22.0
4,2023-10-01T10:03:00,Alert sent to bob123@domain.co.uk,,
5,2023-10-01T10:04:00,Shutdown initiated by z_user@sub.domain.com,25.0
"""

with open("/home/user/raw_sensor_data.csv", "wb") as f:
    f.write(data.encode('iso-8859-1'))
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
