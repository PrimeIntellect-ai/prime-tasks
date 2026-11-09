#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create files using Python to ensure correct byte values
    python3 -c "
import os
os.makedirs('/home/user/recovered_data', exist_ok=True)
files = {
    'chunk_01': b'\x89\x50\x4e\x47\x00\x01\x02\x03\x04',
    'chunk_02': b'\x25\x50\x44\x46\x00\x01\x02\x03\x04',
    'chunk_04': b'\xff\xd8\xff\xe0\x00\x01\x02\x03\x04',
    'chunk_05': b'\x7f\x45\x4c\x46\x00\x01\x02\x03\x04',
    'chunk_07': b'\x89\x50\x4e\x47\x99\x99\x99\x99\x99',
    'chunk_11': b'\x00\x00\x00\x00\x00\x01\x02\x03\x04',
}
for name, content in files.items():
    with open(f'/home/user/recovered_data/{name}', 'wb') as f:
        f.write(content)
"

    # Create duplicates
    cp /home/user/recovered_data/chunk_01 /home/user/recovered_data/chunk_03
    cp /home/user/recovered_data/chunk_02 /home/user/recovered_data/chunk_06
    cp /home/user/recovered_data/chunk_04 /home/user/recovered_data/chunk_08
    cp /home/user/recovered_data/chunk_05 /home/user/recovered_data/chunk_09
    cp /home/user/recovered_data/chunk_04 /home/user/recovered_data/chunk_10

    chmod -R 777 /home/user
