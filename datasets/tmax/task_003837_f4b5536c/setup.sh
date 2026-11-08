#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/storage_task/chunks

    # Safe files
    echo -n "Hello " > /home/user/storage_task/chunks/chunk_0.bin
    echo -n "World!" > /home/user/storage_task/chunks/chunk_1.bin
    echo -n "Data file content" > /home/user/storage_task/chunks/chunk_2.bin

    # Malicious/escape files
    echo -n "Malicious content" > /home/user/storage_task/chunks/chunk_3.bin
    echo -n "More bad stuff" > /home/user/storage_task/chunks/chunk_4.bin

    cat << 'EOF' > /home/user/storage_task/manifest.jsonl
{"chunk": "chunk_1.bin", "target": "hello.txt", "offset": 6}
{"chunk": "chunk_0.bin", "target": "hello.txt", "offset": 0}
{"chunk": "chunk_2.bin", "target": "data/info.bin", "offset": 0}
{"chunk": "chunk_3.bin", "target": "../escaped.txt", "offset": 0}
{"chunk": "chunk_4.bin", "target": "/etc/fake_passwd", "offset": 0}
{"chunk": "chunk_3.bin", "target": "data/../../root.txt", "offset": 0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
