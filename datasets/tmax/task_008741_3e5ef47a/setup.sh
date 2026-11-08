#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    python3 -c "
import os
import struct

files = [
    {
        'path': 'src/Main-File.txt',
        'encoding_flag': 1,
        'content': 'Café'.encode('windows-1252')
    },
    {
        'path': '../outside-file.txt',
        'encoding_flag': 2,
        'content': 'Hello World'.encode('utf-16le')
    },
    {
        'path': 'deep/dir/../../../secret-Data.txt',
        'encoding_flag': 0,
        'content': 'Secret information here.'.encode('utf-8')
    }
]

with open('/home/user/data/legacy_project.pack', 'wb') as f:
    f.write(b'PACK')
    f.write(struct.pack('<I', len(files)))
    for file in files:
        path_bytes = file['path'].encode('utf-8')
        f.write(struct.pack('<H', len(path_bytes)))
        f.write(path_bytes)
        f.write(struct.pack('B', file['encoding_flag']))
        f.write(struct.pack('<I', len(file['content'])))
        f.write(file['content'])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
