#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import json
import gzip
import subprocess

os.makedirs('/home/user/app_logs', exist_ok=True)

# File 1: Valid
log1 = [
    {'timestamp': '2023-10-01T10:00:00Z', 'status': 'OK', 'error_id': ''},
    {'timestamp': '2023-10-01T10:05:00Z', 'status': 'FATAL', 'error_id': 'ERR-001'}
]
with gzip.open('/home/user/app_logs/log_01.gz', 'wt') as f:
    for line in log1:
        f.write(json.dumps(line) + '\n')

# File 2: Truncated
log2 = [
    {'timestamp': '2023-10-01T10:10:00Z', 'status': 'FATAL', 'error_id': 'ERR-002'},
    {'timestamp': '2023-10-01T10:15:00Z', 'status': 'OK', 'error_id': ''}
]
temp_log2 = '/tmp/log2.json'
with open(temp_log2, 'w') as f:
    for line in log2:
        f.write(json.dumps(line) + '\n')
subprocess.run(['gzip', '-c', temp_log2], stdout=open('/home/user/app_logs/log_02.gz', 'wb'))
# Truncate the file to corrupt the gzip trailer and the last line
subprocess.run(['truncate', '-s', '-15', '/home/user/app_logs/log_02.gz'])

# File 3: Valid
log3 = [
    {'timestamp': '2023-10-01T10:20:00Z', 'status': 'FATAL', 'error_id': 'ERR-003'}
]
with gzip.open('/home/user/app_logs/log_03.gz', 'wt') as f:
    for line in log3:
        f.write(json.dumps(line) + '\n')
"

    chmod -R 777 /home/user
