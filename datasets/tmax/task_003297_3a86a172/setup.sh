#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    python3 -c "
import codecs
data = [
    'timestamp,device_id,value\n',
    '2023-10-01T10:00:00Z,D1,10\n',
    '2023-10-01T10:01:00Z,D1,15\n',
    '2023-10-01T10:01:00Z,D1,15\n',
    '2023-10-01T10:02:00Z,D1,20\n',
    '2023-10-01T10:03:00Z,D1,25\n',
    '2023-10-01T10:00:00Z,D2,100\n',
    '2023-10-01T10:02:00Z,D2,200\n',
    '2023-10-01T10:02:00Z,D2,200\n',
    '2023-10-01T10:05:00Z,D2,150\n',
    '2023-10-01T10:06:00Z,D2,300\n'
]
with open('/home/user/raw_etl_dump.dat', 'wb') as f:
    for line in data:
        f.write(line.encode('utf-16le'))
"

    chmod -R 777 /home/user
