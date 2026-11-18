#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    python3 -c "
import os
import tarfile
import struct

os.makedirs('/home/user', exist_ok=True)

files = {
    'main.c': b'#include <stdio.h>\n\nint main() {\n    DEPRECATED_API_CALL();\n    return 0;\n}\n',
    'utils.c': b'void helper() {\n    DEPRECATED_API_CALL();\n}\n',
    'bad.c': b'void corrupted_func() {\n    DEPRECATED_API_CALL();\n}\n'
}

os.makedirs('/tmp/project_setup', exist_ok=True)
for name, content in files.items():
    with open(f'/tmp/project_setup/{name}', 'wb') as f:
        f.write(content)

with tarfile.open('/home/user/project.tar', 'w') as tar:
    for name in files.keys():
        tar.add(f'/tmp/project_setup/{name}', arcname=name)

def calc_xor(data):
    chk = 0
    for b in data:
        chk ^= b
    return chk

with open('/home/user/hashes.bin', 'wb') as f:
    for name, content in files.items():
        chk = calc_xor(content)
        if name == 'bad.c':
            chk ^= 0xFF
        b_name = name.encode('utf-8')
        record = struct.pack('<31sB', b_name, chk)
        f.write(record)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
