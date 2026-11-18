#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import struct
import os

def create_cpk(filepath, entries):
    with open(filepath, 'wb') as f:
        f.write(b'CPK1')
        f.write(struct.pack('<I', len(entries)))
        for name, data in entries:
            name_bytes = name.encode('utf-8')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

entries = [
    ('safe_config.txt', b'port=8080\nmax_connections=100'),
    ('nested/app.json', b'{\"status\": \"ok\"}'),
    ('../../../etc/shadow', b'root:!:18755:0:99999:7:::'),
    ('/var/log/system.log', b'fake log data'),
    ('safe_scripts/run.sh', b'echo \'running\'')
]

os.makedirs('/home/user', exist_ok=True)
create_cpk('/home/user/update.cpk', entries)
"

    chmod -R 777 /home/user
