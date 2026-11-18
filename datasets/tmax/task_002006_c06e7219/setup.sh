#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_temp.csv
timestamp,temp
2023-10-01T09:59:00Z,20.0
2023-10-01T10:05:00Z,26.0
2023-10-01T10:11:00Z,20.0
EOF

    cat << 'EOF' > /home/user/sensor_press.csv
timestamp,pressure
2023-10-01T09:59:00Z,1010
2023-10-01T10:04:30Z,1015
2023-10-01T10:11:00Z,1012
EOF

    cat << 'EOF' > /home/user/validate.py
import csv
import math

expected_data = {
    "2023-10-01T10:00:00Z": (21.0, 1010.0),
    "2023-10-01T10:01:00Z": (22.0, 1010.0),
    "2023-10-01T10:02:00Z": (23.0, 1010.0),
    "2023-10-01T10:03:00Z": (24.0, 1010.0),
    "2023-10-01T10:04:00Z": (25.0, 1010.0),
    "2023-10-01T10:05:00Z": (26.0, 1015.0),
    "2023-10-01T10:06:00Z": (25.0, 1015.0),
    "2023-10-01T10:07:00Z": (24.0, 1015.0),
    "2023-10-01T10:08:00Z": (23.0, 1015.0),
    "2023-10-01T10:09:00Z": (22.0, 1015.0),
    "2023-10-01T10:10:00Z": (21.0, 1015.0),
}

try:
    with open('/home/user/aligned_sensors.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

        if len(rows) != 11:
            print("Row count mismatch")
            exit(1)

        for row in rows:
            ts = row['timestamp']
            if ts not in expected_data:
                print(f"Unexpected timestamp: {ts}")
                exit(1)

            e_temp, e_press = expected_data[ts]
            temp = float(row['temp'])
            press = float(row['pressure'])

            if not math.isclose(temp, e_temp, rel_tol=1e-5):
                print(f"Mismatch in temp at {ts}. Expected {e_temp}, got {temp}")
                exit(1)

            if not math.isclose(press, e_press, rel_tol=1e-5):
                print(f"Mismatch in press at {ts}. Expected {e_press}, got {press}")
                exit(1)

    print("SUCCESS")
    exit(0)
except Exception as e:
    print(f"Validation failed: {e}")
    exit(1)
EOF

    chmod +x /home/user/validate.py
    chmod -R 777 /home/user
