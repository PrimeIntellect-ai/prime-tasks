#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/generate_data.py
import csv
import math

def generate():
    with open('/home/user/data/sensor_logs.csv', 'w', encoding='cp1252', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'lat', 'lon', 'temperature'])

        base_lat = 40.7128
        base_lon = -74.0060
        base_temp = 20.0
        ts = 1600000000

        # Valid row
        writer.writerow([ts, base_lat, base_lon, base_temp])

        # Row 2: Valid, 10 seconds later, moved a bit
        ts += 10
        writer.writerow([ts, base_lat + 0.001, base_lon + 0.001, ""]) # Missing temp

        # Row 3: Valid, 10 seconds later
        ts += 10
        writer.writerow([ts, base_lat + 0.002, base_lon + 0.002, 22.0]) # Temp interpolates row 2 to 21.0

        # Row 4: Anomaly! Jumped 10 degrees in 10 seconds
        ts += 10
        writer.writerow([ts, base_lat + 10.0, base_lon + 10.0, 99.0])

        # Row 5: Valid (relative to row 3)
        ts += 10
        writer.writerow([ts, base_lat + 0.003, base_lon + 0.003, ""])

        # Row 6: Valid
        ts += 10
        writer.writerow([ts, base_lat + 0.004, base_lon + 0.004, 25.0]) # Interpolates row 5 to 23.5

generate()
EOF
    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chmod -R 777 /home/user
