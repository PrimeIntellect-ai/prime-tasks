#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import struct
import random

def setup():
    random.seed(42)
    clean_count = 0

    with open('/home/user/sensor_data.bin', 'wb') as f:
        # Generate 100,000 records
        for i in range(100000):
            # To ensure proper testing, we randomly distribute E1 and E2
            is_e1 = random.choice([True, False])
            is_e2 = random.choice([True, False])

            if is_e1:
                temp = random.choice([-10.0, 60.0])
            else:
                temp = 25.0

            if is_e2:
                status = 1
            else:
                status = 0

            humidity = random.uniform(20.0, 80.0)

            # Pack: id (int), temp (float), humidity (float), status (int)
            f.write(struct.pack('iffi', i, temp, humidity, status))

            if not (is_e1 and is_e2):
                clean_count += 1

    with open('/home/user/.expected_clean_count', 'w') as f:
        f.write(str(clean_count))

if __name__ == '__main__':
    setup()
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
