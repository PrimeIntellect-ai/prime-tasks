#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick cargo
    pip3 install pytest pandas

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /app

    # Generate the specs image using ImageMagick
    convert -background white -fill black -font Courier -pointsize 18 label:"QUALITY CONTROL SPECS\n\nPressure_Sensor:\nExpected Mean: 105.0\nExpected StdDev: 4.2\n\nTemp_Sensor:\nExpected Mean: 298.5\nExpected StdDev: 1.1\n\nFlag any reading that deviates by more than 2.5 standard deviations from the expected mean." /app/specs.png

    # Generate synthetic data
    cat << 'EOF' > /tmp/gen_data.py
import csv
import random

random.seed(42)
with open('/home/user/data/readings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['row_id', 'timestamp', 'sensor_name', 'value'])
    for i in range(1, 10001):
        sensor = random.choice(['Pressure_Sensor', 'Temp_Sensor', 'Other_Sensor'])
        if sensor == 'Pressure_Sensor':
            mean, std = 105.0, 4.2
        elif sensor == 'Temp_Sensor':
            mean, std = 298.5, 1.1
        else:
            mean, std = 50.0, 10.0

        val = random.gauss(mean, std)
        if random.random() < 0.05:
            val += random.choice([-1, 1]) * std * random.uniform(2.6, 5.0)

        writer.writerow([i, f'2023-01-01T12:00:{i%60:02d}Z', sensor, round(val, 2)])
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
