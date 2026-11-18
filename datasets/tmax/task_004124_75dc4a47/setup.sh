#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 file
    pip3 install pytest pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import csv
from datetime import datetime, timedelta

sensors = {
    'SENS_A': {'count': 100, 'temp': 15.5},
    'SENS_B': {'count': 50, 'temp': 22.0},
    'SENS_C': {'count': 200, 'temp': 8.4}
}

start_time = datetime(2023, 1, 1, 0, 0, 0)

with open('sensor_data_raw.csv', 'w', encoding='iso-8859-1', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'sensor_id', 'temperature', 'status'])

    for s_id, data in sensors.items():
        for i in range(data['count']):
            ts = start_time + timedelta(minutes=i)
            # Add some special ISO-8859-1 characters (e.g., degree symbol °, é, etc.)
            status = f"Température mesurée à {data['temp']}°C"
            writer.writerow([ts.isoformat(), s_id, data['temp'], status])
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
