#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace gcc
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create pysniff-telemetry package
    mkdir -p /app/pysniff-telemetry/pysniff

    cat << 'EOF' > /app/pysniff-telemetry/setup.py
from setuptools import setup, find_packages
setup(name='pysniff-telemetry', version='1.0', packages=find_packages())
EOF

    cat << 'EOF' > /app/pysniff-telemetry/pysniff/__init__.py
from .parser import parse_file
EOF

    cat << 'EOF' > /app/pysniff-telemetry/pysniff/parser.py
import struct

def parse_header(data):
    # Bug: Always assumes 32-bit little-endian timestamp, causing struct.error on 64-bit drops
    timestamp = struct.unpack('<I', data[1:5])[0]
    return timestamp

def parse_event_id(data, bitness):
    offset = 5 if bitness == 1 else 9
    return data[offset:offset+8].decode('utf-8').strip('\x00')

def parse_file(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    if not data:
        return None
    bitness = data[0]
    timestamp = float(parse_header(data))
    event_id = parse_event_id(data, bitness)
    return {"timestamp": timestamp, "event_id": event_id}
EOF

    cd /app/pysniff-telemetry && pip3 install -e .

    # Create malware_dropper
    cat << 'EOF' > /tmp/malware_dropper.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int main() {
    char *debug = getenv("DEBUG_DROP");
    if (debug && strcmp(debug, "1") == 0) {
        mkdir("/home/user/.cache", 0777);
        mkdir("/home/user/.cache/telemetry_drops", 0777);

        FILE *f1 = fopen("/home/user/.cache/telemetry_drops/drop1.bin", "wb");
        if (f1) {
            unsigned char data[13] = {
                0x01, 
                0x10, 0x27, 0x00, 0x00, // 10000
                'E', 'V', 'T', '_', '0', '0', '0', '1'
            };
            fwrite(data, 1, 13, f1);
            fclose(f1);
        }

        FILE *f2 = fopen("/home/user/.cache/telemetry_drops/drop2.bin", "wb");
        if (f2) {
            unsigned char data[17] = {
                0x02, 
                0x20, 0x4e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 20000
                'E', 'V', 'T', '_', '0', '0', '0', '2'
            };
            fwrite(data, 1, 17, f2);
            fclose(f2);
        }
    }
    return 0;
}
EOF
    gcc /tmp/malware_dropper.c -o /home/user/malware_dropper
    chmod +x /home/user/malware_dropper
    rm /tmp/malware_dropper.c

    # Create golden timeline
    mkdir -p /opt/eval
    cat << 'EOF' > /opt/eval/golden_timeline.json
[
    {"timestamp": 10000.0, "event_id": "EVT_0001"},
    {"timestamp": 20000.0, "event_id": "EVT_0002"}
]
EOF

    chmod -R 777 /home/user
