#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import struct
import os

os.makedirs('/home/user', exist_ok=True)

with open('/home/user/quotas.csv', 'w') as f:
    f.write('101,1000\n')
    f.write('102,2000\n')
    f.write('103,500\n')
    f.write('104,3000\n')

records = [
    (1600000000, 101, 500),
    (1600000010, 102, 1000),
    (1600000020, 101, 600),
    (1600000030, 103, 200),
    (1600000040, 104, 3000),
    (1600000050, 101, -50),
    (1600000060, 102, 500),
    (1600000070, 103, 400),
    (1600000080, 104, -100)
]

with open('/home/user/allocations.wal', 'wb') as f:
    for ts, uid, delta in records:
        f.write(struct.pack('<QIi', ts, uid, delta))

os.chmod('/home/user/quotas.csv', 0o644)
os.chmod('/home/user/allocations.wal', 0o644)
"

    chmod -R 777 /home/user
