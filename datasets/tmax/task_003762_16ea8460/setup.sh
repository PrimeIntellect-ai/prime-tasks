#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/anomalies.wav "The following machines require immediate inspection: Alpha seven three bravo, delta niner zero epsilon, and omega two two x-ray."

    # Generate telemetry.csv
    cat << 'EOF' > /tmp/gen_telemetry.py
import csv
import os

os.makedirs('/app', exist_ok=True)

with open('/app/telemetry.csv', 'wb') as f:
    f.write(b"timestamp,machine_id,temperature,sensor_reading,status_notes\n")
    # Valid A73B
    f.write(b"2023-10-01T10:00:00Z,A73B,45.2,100,Normal operation\n")
    # Duplicate A73B
    f.write(b"2023-10-01T10:00:00Z,A73B,46.0,105,Ignored duplicate\n")
    # Invalid temp A73B
    f.write(b"2023-10-01T10:05:00Z,A73B,200.0,110,Too hot\n")
    # Valid D90E with ISO-8859-1 notes
    line = "2023-10-01T10:10:00Z,D90E,10.5,50,System offline due to r\xe9sum\xe9\n"
    f.write(line.encode('iso-8859-1'))
    # Valid O22X
    f.write(b"2023-10-01T10:15:00Z,O22X,-10.0,10,Cold start\n")
    # Irrelevant
    f.write(b"2023-10-01T10:20:00Z,X99Y,20.0,20,Normal\n")
EOF
    python3 /tmp/gen_telemetry.py
    rm /tmp/gen_telemetry.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
