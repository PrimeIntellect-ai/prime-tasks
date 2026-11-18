#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import gzip
import json

os.makedirs('/home/user/archives/2023/10/01', exist_ok=True)
os.makedirs('/home/user/archives/2023/10/02', exist_ok=True)

auth_logs = [
    {'timestamp': '2023-10-01T08:00:00Z', 'service': 'auth', 'level': 'INFO', 'stack_trace': ''},
    {'timestamp': '2023-10-01T08:05:00Z', 'service': 'auth', 'level': 'FATAL', 'stack_trace': 'ConnectionError: DB unreachable\n  at db_conn.py:42\n  at main.py:10'},
    {'timestamp': '2023-10-01T08:10:00Z', 'service': 'auth', 'level': 'ERROR', 'stack_trace': 'Retry failed'}
]

payment_logs = [
    {'timestamp': '2023-10-02T09:15:00Z', 'service': 'payment', 'level': 'FATAL', 'stack_trace': 'NullPointerException\n  at payment_processor.py:112'},
    {'timestamp': '2023-10-02T09:20:00Z', 'service': 'payment', 'level': 'INFO', 'stack_trace': ''},
    {'timestamp': '2023-10-01T07:50:00Z', 'service': 'payment', 'level': 'FATAL', 'stack_trace': 'OutOfMemoryError\n  at memory_alloc.c:120\n  at wrapper.py:12\n  at init.py:1\n  at main.py:5'}
]

with gzip.open('/home/user/archives/2023/10/01/auth.json.gz', 'wt') as f:
    for log in auth_logs:
        f.write(json.dumps(log) + '\n')

with gzip.open('/home/user/archives/2023/10/02/payment.json.gz', 'wt') as f:
    for log in payment_logs:
        f.write(json.dumps(log) + '\n')
"

    chmod -R 777 /home/user
