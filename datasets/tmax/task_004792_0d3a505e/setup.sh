#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest pandas numpy setuptools

    mkdir -p /app/logs
    cd /app

    # Generate dataset and ground truth
    cat << 'EOF' > /app/generate_data.py
import os
import tarfile
import random
import pandas as pd

os.makedirs('/app/logs', exist_ok=True)
random.seed(42)

stations = [101, 202, 303, 404, 505]
encodings = ['utf-8', 'iso-8859-1', 'windows-1252']

records = []
for i in range(1000):
    station = random.choice(stations)
    temp = round(random.uniform(10.0, 35.0), 2)
    humid = round(random.uniform(30.0, 90.0), 2)
    records.append({'StationID': station, 'Temperature': temp, 'Humidity': humid})

    lines = []
    lines.append(f"StationID: {station}")
    if random.random() < 0.4:
        lines.append("[DIAGNOSTIC_START]")
        lines.append("CPU_TEMP: 85C")
        lines.append("MEM_USAGE: 99%")
        lines.append("ERROR_CODE: 0x1A4")
        lines.append("[DIAGNOSTIC_END]")
    lines.append(f"Temperature: {temp}")
    lines.append(f"Humidity: {humid}")

    content = "\n".join(lines) + "\n"
    encoding = random.choice(encodings)

    with open(f"/app/logs/log_{i}.txt", "w", encoding=encoding) as f:
        f.write(content)

with tarfile.open("/app/sensor_logs.tar.gz", "w:gz") as tar:
    tar.add("/app/logs", arcname="logs")

df = pd.DataFrame(records)
truth = df.groupby('StationID').mean().reset_index()
truth['AvgTemp'] = truth['Temperature']
truth['AvgHumid'] = truth['Humidity']
truth[['StationID', 'AvgTemp', 'AvgHumid']].to_csv("/app/ground_truth_averages.csv", index=False)
EOF

    python3 /app/generate_data.py
    rm -rf /app/logs /app/generate_data.py

    # Download and setup chardet
    wget -q https://github.com/chardet/chardet/archive/refs/tags/5.2.0.tar.gz
    tar -xzf 5.2.0.tar.gz
    mv chardet-5.2.0 chardet
    rm 5.2.0.tar.gz

    # Overwrite setup.py to include the syntax error perturbation
    cat << 'EOF' > /app/chardet/setup.py
from setuptools import setup, find_packages

setup(
    name="chardet",
    version="5.2.0",
    packages=find_packages(),
    author="Mark Pilgrim"
    author_email="mark@diveintomark.org",
    description="Universal encoding detector for Python 3",
)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
