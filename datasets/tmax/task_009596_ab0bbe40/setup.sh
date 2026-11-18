#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    python3 -c "
import os

data_utf16 = '''[2023-10-01 14:15:30] IP:192.168.1.10 CPU:45% MEM:1024MB STATUS:OK
[2023-10-01 14:45:00] IP:192.168.1.10 CPU:55% MEM:2048MB STATUS:OK
[2023-10-01 14:50:00] IP:192.168.1.10 CPU:105% MEM:1024MB STATUS:ERROR
[2023-10-01 14:55:00] IP:192.168.1.10 CPU:-5% MEM:512MB STATUS:OK
[2023-10-01 16:10:00] IP:192.168.1.10 CPU:30% MEM:512MB STATUS:OK
'''

data_iso = '''[2023-10-01 15:05:00] IP:10.0.0.5 CPU:80% MEM:4096MB STATUS:OK
[2023-10-01 15:30:00] IP:10.0.0.5 CPU:90% MEM:8192MB STATUS:OK
[2023-10-01 15:40:00] IP:999.999.999.999 CPU:10% MEM:512MB STATUS:OK
[2023-10-01 15:45:00] IP:10.0.0.5 CPU:85% MEM:2048MB STATUS:WARNING
Corrupted log line without proper formatting...
'''

with open('/home/user/raw_logs/server1.log', 'w', encoding='utf-16le') as f:
    f.write(data_utf16)

with open('/home/user/raw_logs/server2.log', 'w', encoding='iso-8859-1') as f:
    f.write(data_iso)
"

    chmod -R 777 /home/user
