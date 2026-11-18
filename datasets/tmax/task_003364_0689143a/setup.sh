#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data/snapshots
    mkdir -p /home/user/archive_setup

    cat << 'EOF' > /home/user/backup_config.json
{
  "source_dir": "/home/user/data/snapshots",
  "archive_dir": "/home/user/archive",
  "expected_magic": [83, 78, 65, 80, 66, 75, 80, 0]
}
EOF

    cat << 'EOF' > /home/user/data/sync.log
[TRANSACTION]
ID: 101
Status: SUCCESS
File: snap_101.bin
[/TRANSACTION]
[TRANSACTION]
ID: 102
Status: FAILED
File: snap_102.bin
[/TRANSACTION]
[TRANSACTION]
ID: 103
Status: SUCCESS
File: snap_103.bin
[/TRANSACTION]
[TRANSACTION]
ID: 104
Status: SUCCESS
File: snap_104.bin
[/TRANSACTION]
[TRANSACTION]
ID: 105
Status: PENDING
File: snap_105.bin
[/TRANSACTION]
EOF

    python3 -c "
import os
files = {
    'snap_101.bin': b'\x53\x4E\x41\x50\x42\x4B\x50\x00\x01\x02\x03\x04',
    'snap_102.bin': b'\x53\x4E\x41\x50\x42\x4B\x50\x00\x0A\x0B\x0C\x0D',
    'snap_103.bin': b'\x53\x4E\x41\x50\x45\x52\x52\x00\x11\x22\x33\x44',
    'snap_104.bin': b'\x53\x4E\x41\x50\x42\x4B\x50\x00\x99\x88\x77\x66',
    'snap_105.bin': b'\x53\x4E\x41\x50\x42\x4B\x50\x00\xAA\xBB\xCC\xDD'
}
for f, data in files.items():
    with open(f'/home/user/data/snapshots/{f}', 'wb') as out:
        out.write(data)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chown user:user /home/user/backup_config.json
    chmod -R 777 /home/user
