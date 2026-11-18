#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    # Create the original parser.py (which has the signed integer overflow bug)
    cat << 'EOF' > parser.py
import struct
import json

def process_trace(filepath):
    events = []
    with open(filepath, 'rb') as f:
        while True:
            hdr = f.read(8)
            if not hdr or len(hdr) < 8:
                break

            # BUG: Unpacking as signed 32-bit integers ('<ii'). 
            # Timestamps exceeding 2147483647 will overflow and become negative.
            ts, duration = struct.unpack('<ii', hdr)

            if len(events) > 0 and ts < events[-1]['ts']:
                raise ValueError(f"Time went backwards! Current ts: {ts}, previous ts: {events[-1]['ts']}")

            events.append({"ts": ts, "duration": duration})

    with open('/home/user/app/summary.json', 'w') as out:
        json.dump({"event_count": len(events), "last_ts": events[-1]['ts']}, out)
EOF

    # Compile to parser.pyc and remove the source
    python3 -m py_compile parser.py
    mv __pycache__/parser.*.pyc parser.pyc
    rm -rf __pycache__ parser.py

    # Create main.py
    cat << 'EOF' > main.py
import sys
import os
from parser import process_trace

if __name__ == "__main__":
    trace_file = "/home/user/app/trace.dat"
    if not os.path.exists(trace_file):
        print(f"Error: {trace_file} not found.")
        sys.exit(1)

    print(f"Processing {trace_file}...")
    process_trace(trace_file)
    print("Success! Output written to summary.json")
EOF

    # Create the binary trace.dat file with an intentional overflow trigger
    python3 -c "
import struct
with open('trace.dat', 'wb') as f:
    # Record 1: Normal timestamp
    f.write(struct.pack('<II', 1600000000, 15))
    # Record 2: Nearing the signed 32-bit integer max
    f.write(struct.pack('<II', 2147483640, 20))
    # Record 3: Overflowing signed 32-bit max (0x80000005 = 2147483653)
    f.write(struct.pack('<II', 2147483653, 25))
    # Record 4: Further overflow
    f.write(struct.pack('<II', 2147483700, 10))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
