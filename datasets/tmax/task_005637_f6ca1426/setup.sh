#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/daemon.py
import struct
import sys

# Magic bytes: 0xDEADBEEF
MAGIC = b'\xef\xbe\xad\xde'
# Format: Magic (4s), Timestamp_ms (signed int32), Status (int8)
RECORD_FORMAT = '<4s i b'
RECORD_SIZE = struct.calcsize(RECORD_FORMAT)

def parse_wal(filepath):
    total_uptime = 0
    last_time = None
    last_status = None

    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(RECORD_SIZE)
            if not chunk:
                break

            if len(chunk) < RECORD_SIZE:
                print("Incomplete record at end of file.")
                break

            magic, timestamp, status = struct.unpack(RECORD_FORMAT, chunk)

            if magic != MAGIC:
                raise ValueError("Corrupt WAL: Invalid magic bytes!")

            if last_time is not None and last_status == 1:
                duration = timestamp - last_time
                if duration < 0:
                    raise ValueError(f"Negative duration detected! {timestamp} - {last_time} = {duration}")
                total_uptime += duration

            last_time = timestamp
            last_status = status

    return total_uptime

if __name__ == '__main__':
    try:
        uptime = parse_wal('wal.dat')
        print(f"Total Uptime: {uptime} ms")
    except Exception as e:
        print(f"Crash: {e}")
EOF

    cat << 'EOF' > /home/user/app/error.log
Traceback (most recent call last):
  File "/home/user/app/daemon.py", line 42, in <module>
    uptime = parse_wal('wal.dat')
  File "/home/user/app/daemon.py", line 32, in parse_wal
    raise ValueError(f"Negative duration detected! {timestamp} - {last_time} = {duration}")
ValueError: Negative duration detected! -1294967296 - 5000 = -1294972296
EOF

    python3 -c "import os; open('/home/user/app/wal.dat', 'wb').write(b'\xef\xbe\xad\xde\xe8\x03\x00\x00\x01\xef\xbe\xad\xde\x88\x13\x00\x00\x00\x00\x11\"3DUf\xef\xbe\xad\xde\x00\x945\xb2\x01\xef\xbe\xad\xde|\xa95\xb2\x00')"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
