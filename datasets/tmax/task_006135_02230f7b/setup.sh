#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the incoming_data directory
    mkdir -p /home/user/incoming_data

    # Generate the initial state using a Python script
    python3 -c "
import csv
import random
import tarfile
import zipfile
import os

random.seed(42)

def generate_csv(filename, rows):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'server_id', 'metric_value', 'status'])
        for i in range(rows):
            ts = random.randint(1600000000, 1700000000)
            srv = f'srv_{random.randint(1,10)}'
            val = random.randint(-50, 200)
            status = random.choice(['OK', 'ERROR', 'WARN', 'DEBUG'])
            writer.writerow([ts, srv, val, status])

generate_csv('file1.csv', 600)
generate_csv('file2.csv', 400)
generate_csv('file3.csv', 200)

with tarfile.open('/home/user/incoming_data/archive1.tar.gz', 'w:gz') as tar:
    tar.add('file1.csv')
    tar.add('file2.csv')

with zipfile.ZipFile('inner.zip', 'w') as z:
    z.write('file3.csv')

with tarfile.open('/home/user/incoming_data/archive2.tar', 'w') as tar:
    tar.add('inner.zip')

os.remove('file1.csv')
os.remove('file2.csv')
os.remove('file3.csv')
os.remove('inner.zip')
"

    chmod -R 777 /home/user
