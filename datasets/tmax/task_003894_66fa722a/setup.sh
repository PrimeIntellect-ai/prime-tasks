#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import struct
import os

def make_t_record(text):
    text_bytes = text.encode('utf-8')
    header = struct.pack('<BI', ord('T'), len(text_bytes))
    return header + text_bytes

def make_l_record(offset):
    return struct.pack('<BI', ord('L'), offset)

records = []
records.append(make_t_record("Project_Start\n")) # 0
records.append(make_l_record(40))                # 19
records.append(make_t_record("Orphaned_Data\n")) # 24
records.append(b'\x00')                          # 39
records.append(make_t_record("Module_Active\n")) # 40
records.append(make_l_record(80))                # 59
records.append(make_t_record("Garbage_Text\n"))  # 64
records.append(b'\x00' * 3)                      # 77
records.append(make_t_record("Config_Loaded\n")) # 80
records.append(make_l_record(19))                # 99

with open('/home/user/project_data.bin', 'wb') as f:
    f.write(b''.join(records))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
