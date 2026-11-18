#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_logs.py
import random
from datetime import datetime, timedelta

random.seed(42)

types = ["TEMP", "HUMID", "PRESSURE"]
start_time = datetime(2023, 10, 24, 12, 0, 0)

with open("/home/user/iot_sensors.log", "w") as f:
    # Valid lines
    for i in range(1000):
        t = start_time + timedelta(seconds=random.randint(0, 10000))
        sens_id = f"{random.randint(1000, 9999)}"
        sens_type = random.choice(types)
        status = "OK" if random.random() < 0.8 else "ERROR"
        payload = f"{random.uniform(10.0, 50.0):.2f}"
        f.write(f"[{t.strftime('%Y-%m-%d %H:%M:%S')}] [SENS-{sens_id}:{sens_type}] {status} {payload}\n")

    # Invalid lines (malformed)
    f.write("[2023-10-24 14:99:99] [SENS-123:TEMP] OK 22.0\n")
    f.write("[2023-10-24 14:22:11] [SENS-12A3:TEMP] OK 22.0\n")
    f.write("[2023-10-24 14:22:11] [SENS-1234:temp] OK 22.0\n")
    f.write("2023-10-24 14:22:11 [SENS-1234:TEMP] OK 22.0\n")
    f.write("[2023-10-24 14:22:11] [SENS-1234:TEMP] WARNING 22.0\n")

EOF
    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    chmod -R 777 /home/user
