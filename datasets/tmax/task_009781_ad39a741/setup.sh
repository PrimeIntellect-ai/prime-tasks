#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/artifacts/dir1/dir2', exist_ok=True)
os.makedirs('/home/user/artifacts/dir3', exist_ok=True)
os.makedirs('/home/user/curated', exist_ok=True)

with open('/home/user/artifacts/bin1', 'wb') as f:
    f.write(b'\x7F\x45\x4C\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3E\x00')

with open('/home/user/artifacts/dir1/dir2/bin2', 'wb') as f:
    f.write(b'\x7F\x45\x4C\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3E\x00')

with open('/home/user/artifacts/dir1/bin_32', 'wb') as f:
    f.write(b'\x7F\x45\x4C\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00')

with open('/home/user/artifacts/dir3/readme.txt', 'w') as f:
    f.write('Hello World\n')

with open('/home/user/artifacts/dir1/dir2/short', 'wb') as f:
    f.write(b'\x7F\x45')
"

    chown -R user:user /home/user/artifacts /home/user/curated
    chmod -R 777 /home/user
