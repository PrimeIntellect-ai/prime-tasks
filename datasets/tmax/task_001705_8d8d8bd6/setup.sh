#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import struct
import os

def write_record(f, ts, enc, msg):
    if enc == 1:
        msg_bytes = msg.encode('utf-16le')
    else:
        msg_bytes = msg.encode('utf-8')

    f.write(struct.pack('<Q', ts))
    f.write(struct.pack('<B', enc))
    f.write(struct.pack('<H', len(msg_bytes)))
    f.write(msg_bytes)

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/logs.bin', 'wb') as f:
    t_start = 1700000000

    # Bucket 0
    write_record(f, t_start + 10, 0, 'LOGIN user_a')
    write_record(f, t_start + 15, 0, 'LOGIN user_a')
    write_record(f, t_start + 20, 1, 'ERROR db_timeout')

    # Bucket 1 is empty

    # Bucket 2
    write_record(f, t_start + 130, 1, 'WARNING high_cpu')

    # Bucket 3
    write_record(f, t_start + 190, 0, 'LOGOUT user_a')
"

    chmod -R 777 /home/user
