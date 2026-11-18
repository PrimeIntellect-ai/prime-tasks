#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate.py
import os

data_path = "/home/user/sensor_data.csv"
os.makedirs("/home/user", exist_ok=True)

m_true = 3.1415
c_true = -2.7182

with open(data_path, "w") as f:
    f.write("X,Y\n")
    # Clean data
    for i in range(1, 101):
        x = float(i)
        y = m_true * x + c_true
        f.write(f"{x:.4f},{y:.4f}\n")

    # Missing values
    f.write("NA,5.0\n")
    f.write("10.0,NA\n")

    # Outliers
    f.write("2000.0,5000.0\n")
    f.write("-1500.0,0.0\n")
EOF

    python3 /tmp/generate.py
    rm /tmp/generate.py

    chmod -R 777 /home/user
