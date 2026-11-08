#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
data_path = '/home/user/trials.csv'
os.makedirs(os.path.dirname(data_path), exist_ok=True)
with open(data_path, 'w') as f:
    f.write('id,group,success\n')
    data = []
    for i in range(15): data.append(['alpha', 1])
    for i in range(10): data.append(['alpha', 0])
    for i in range(10): data.append(['beta', 1])
    for i in range(20): data.append(['beta', 0])
    for i in range(12): data.append(['gamma', 1])
    for i in range(13): data.append(['gamma', 0])
    for i in range(3): data.append(['alpha', 1])
    for i in range(2): data.append(['alpha', 0])
    for i in range(2): data.append(['beta', 1])
    for i in range(8): data.append(['beta', 0])
    for i in range(1): data.append(['gamma', 1])
    for i in range(4): data.append(['gamma', 0])
    for idx, row in enumerate(data):
        f.write(f'{idx+1},{row[0]},{row[1]}\n')
"

    chmod -R 777 /home/user
