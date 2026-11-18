#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import os
import tarfile
import zipfile

def create_wal_record(timestamp, action, key, value):
    key_bytes = key.encode('utf-8')
    val_bytes = value.encode('utf-8')
    return struct.pack(f'<IBH{len(key_bytes)}sH{len(val_bytes)}s', 
                       timestamp, action, len(key_bytes), key_bytes, len(val_bytes), val_bytes)

def write_wal(filename, records):
    with open(filename, 'wb') as f:
        f.write(b'CWAL\x01') # Header
        for r in records:
            f.write(r)

os.makedirs('/tmp/wal_setup/2023', exist_ok=True)
os.makedirs('/tmp/wal_setup/2024', exist_ok=True)

# 2023 logs (to be ignored)
write_wal('/tmp/wal_setup/2023/log1.wal', [
    create_wal_record(1672531200, 2, "network.gateway", "192.168.1.1")
])

# 2024 logs
# Valid records (MOD and contains 'network')
r1 = create_wal_record(1704067200, 2, "system.network.dns", "8.8.8.8")
r2 = create_wal_record(1705000000, 2, "network.eth0.ip", "10.0.0.5")
r3 = create_wal_record(1705500000, 2, "network.eth0.mtu", "1500")

# Invalid records (wrong action or no 'network')
r4 = create_wal_record(1705000001, 1, "network.eth1.ip", "10.0.0.6") # ADD
r5 = create_wal_record(1705000002, 3, "network.vlan.id", "100") # DEL
r6 = create_wal_record(1706000000, 2, "system.hostname", "server01") # MOD but no network

write_wal('/tmp/wal_setup/2024/01.wal', [r1, r4])
write_wal('/tmp/wal_setup/2024/02.wal', [r2, r5, r6, r3])

# Create tar archives
with tarfile.open('/tmp/wal_setup/logs_2023.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/wal_setup/2023/log1.wal', arcname='log1.wal')

with tarfile.open('/tmp/wal_setup/logs_2024.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/wal_setup/2024/01.wal', arcname='01.wal')
    tar.add('/tmp/wal_setup/2024/02.wal', arcname='02.wal')

# Create zip
os.makedirs('/home/user', exist_ok=True)
with zipfile.ZipFile('/home/user/config_backups.zip', 'w') as zf:
    zf.write('/tmp/wal_setup/logs_2023.tar.gz', 'logs_2023.tar.gz')
    zf.write('/tmp/wal_setup/logs_2024.tar.gz', 'logs_2024.tar.gz')
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/wal_setup /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
