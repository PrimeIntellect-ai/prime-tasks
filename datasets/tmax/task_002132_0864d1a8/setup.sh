#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/logs
    mkdir -p /home/user/data
    mkdir -p /home/user/output

    # Generate the binary file
    python3 -c "
import struct
with open('/home/user/data/batch_01.bin', 'wb') as f:
    for i in range(10):
        f.write(struct.pack('<IIfd', i, 1600000000+i, float(i), float(i*2)))
"

    # Create process.py
    cat << 'EOF' > /home/user/app/process.py
import struct
import json
import os

def process_data():
    sum_sensor2 = 0.0
    # Bug: using old 16-byte format
    record_size = 16
    fmt = '<Ifd'

    with open('/home/user/data/batch_01.bin', 'rb') as f:
        while True:
            chunk = f.read(record_size)
            if not chunk:
                break
            record = struct.unpack(fmt, chunk)
            sum_sensor2 += record[2]

    os.makedirs('/home/user/output', exist_ok=True)
    with open('/home/user/output/result.json', 'w') as f:
        json.dump({"total_sensor2": sum_sensor2}, f)

if __name__ == '__main__':
    process_data()
EOF

    # Create nightly.log
    cat << 'EOF' > /home/user/logs/nightly.log
Running nightly pipeline...
Traceback (most recent call last):
  File "/home/user/app/process.py", line 23, in <module>
    process_data()
  File "/home/user/app/process.py", line 15, in process_data
    record = struct.unpack(fmt, chunk)
struct.error: unpack requires a buffer of 16 bytes
EOF

    # Create Makefile
    cat << 'EOF' > /home/user/app/Makefile
all: run

setup:
	@echo "Setting up environment..."
	mkdir -p /home/user/output
	# Deliberate build failure (typo in command)
	exitt 1

run: setup
	python3 process.py
EOF

    chmod -R 777 /home/user
