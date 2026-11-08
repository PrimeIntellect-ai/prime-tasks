#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest numpy

# Create user
useradd -m -s /bin/bash user || true

# Create data directory
mkdir -p /home/user/data

# Generate the CSV files using the provided Python script
cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import numpy as np
import json

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

def generate_data(n=50, cpu_base=20, mem_base=60, net_in_base=1000, net_out_base=500):
    timestamps = np.arange(1, n+1)
    # create some correlation
    memory = np.random.normal(mem_base, 5, n)
    cpu = 0.5 * memory + np.random.normal(cpu_base - 0.5*mem_base, 2, n)
    net_in = np.random.normal(net_in_base, 50, n)
    net_out = np.random.normal(net_out_base, 30, n)
    return timestamps, cpu, memory, net_in, net_out

def write_csv(filename, data):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Timestamp', 'CPU_Usage', 'Memory_Usage', 'Network_In', 'Network_Out'])
        for i in range(len(data[0])):
            writer.writerow([data[0][i], data[1][i], data[2][i], data[3][i], data[4][i]])

dataA = generate_data(cpu_base=25, mem_base=65)
dataB = generate_data(cpu_base=18, mem_base=42)
dataC = generate_data(cpu_base=26, mem_base=66)

write_csv('/home/user/data/serverA.csv', dataA)
write_csv('/home/user/data/serverB.csv', dataB)
write_csv('/home/user/data/serverC.csv', dataC)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

# Ensure sysmetrics directory does not exist initially
rm -rf /home/user/sysmetrics

# Set permissions
chmod -R 777 /home/user
