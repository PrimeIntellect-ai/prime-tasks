#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/writer.py
import time

def generate_data():
    with open('/home/user/live_sensor.log', 'w') as f:
        for i in range(1, 50001):
            f.write(f"2023-10-25T10:00:00Z,SENSOR_{i%10},{i*1.5}\n")
            f.flush()
            if i % 100 == 0:
                time.sleep(0.01) # Simulate slight delay but keep it relatively fast

if __name__ == "__main__":
    generate_data()
EOF

    chmod -R 777 /home/user
